/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvr.h"

#include "core/backendoutput.h"
#include "core/outputbackend.h"
#include "core/outputconfiguration.h"
#include "input.h"
#include "kwinvr_logging.h"
#include "kwinvrbridge.h"
#include "kwinvrconfigwrapper.h"
#include "kwinvrhelpers.h"
#include "kwinvrshortcuts.h"
#include "pointer_input.h"
#include "window.h"
#include "workspace.h"

#include <KGlobalAccel>
#include <KLocalizedString>

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QFileInfo>
#include <QLibrary>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QStandardPaths>
#include <QTimer>

#include <openxr/openxr.h>

namespace KWin
{

KwinVr::KwinVr()
{
    auto config = KWinVRConfigWrapper::instance();
    m_watcher = KConfigWatcher::create(config->sharedConfig());
    connect(m_watcher.data(), &KConfigWatcher::configChanged, config, &KWinVRConfigWrapper::load);

    // Register shortcuts at plugin load (before VR activation)
    KWinVrShortcuts::instance();

    registerDBusService();

    connect(kwinApp()->outputBackend(), &OutputBackend::outputsQueried, this, &KwinVr::leasableOutputsChanged);
    connect(kwinApp()->outputBackend(), &OutputBackend::outputLeaseStateChanged, this, &KwinVr::leasableOutputsChanged);

    auto cycleAction = new QAction(this);
    connect(cycleAction, &QAction::triggered, this, &KwinVr::onActivateVr);
    cycleAction->setObjectName(QStringLiteral("Activate VR Mode"));
    cycleAction->setText(i18nc("@action Activate VR Mode", "Activate VR Mode"));
    KGlobalAccel::self()->setDefaultShortcut(cycleAction, {{Qt::CTRL | Qt::META | Qt::Key_J}});
    KGlobalAccel::self()->setShortcut(cycleAction, {});

    connect(KwinVrBridge::instance(), &KwinVrBridge::xrFailed, this, [this](const QString &errorString) {
        qCWarning(KWINVR) << "XR failed signal received:" << errorString;
        showNotification(i18n("Failed to Activate VR mode"),
                         i18n("error: %1", errorString),
                         KNotification::CloseOnTimeout);
        stop();
    }, Qt::QueuedConnection);

    connect(&m_xrTest, &OpenXRTest::sessionResult, this, [this](bool success, const QString &message) {
        qCWarning(KWINVR) << "OpenXR test result:" << success << "message:" << message;
        if (success) {
            start();
        } else {
            showNotification(i18n("Failed to Activate VR mode"),
                             i18n("Test Failed: %1", message),
                             KNotification::CloseOnTimeout);
            stop();
        }
    }, Qt::QueuedConnection);
}

KwinVr::~KwinVr()
{
    stop();
    closeNotification();
}

bool KwinVr::vrActive() const
{
    return m_active;
}

bool KwinVr::initOpenXRLoaderWithRuntime(const QString &runtimeJsonPath, QString *errorMessage) const
{
    const QFileInfo runtimeJsonInfo(runtimeJsonPath);
    if (!runtimeJsonInfo.isAbsolute()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("OpenXR runtime JSON path must be absolute");
        }
        return false;
    }

    if (!runtimeJsonInfo.exists()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("OpenXR runtime JSON does not exist: %1").arg(runtimeJsonPath);
        }
        return false;
    }

    QLibrary openXRLoader(QStringLiteral("openxr_loader"));
    if (!openXRLoader.load()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Failed to load OpenXR loader library: %1").arg(openXRLoader.errorString());
        }
        return false;
    }

    const auto pfnXrGetInstanceProcAddr = reinterpret_cast<PFN_xrGetInstanceProcAddr>(openXRLoader.resolve("xrGetInstanceProcAddr"));
    if (!pfnXrGetInstanceProcAddr) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrGetInstanceProcAddr not available in OpenXR loader");
        }
        return false;
    }

    PFN_xrInitializeLoaderKHR pfnInitializeLoaderKHR = nullptr;
    XrResult xr = pfnXrGetInstanceProcAddr(
        XR_NULL_HANDLE,
        "xrInitializeLoaderKHR",
        reinterpret_cast<PFN_xrVoidFunction *>(&pfnInitializeLoaderKHR));

    if (XR_FAILED(xr) || pfnInitializeLoaderKHR == nullptr) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrInitializeLoaderKHR not available (result=%1)").arg(xr);
        }
        return false;
    }

    const QByteArray runtimeJsonAbsPath = runtimeJsonInfo.absoluteFilePath().toUtf8();
    const XrLoaderInitPropertyValueEXT properties[] = {
        {"XR_RUNTIME_JSON", runtimeJsonAbsPath.constData()},
    };

    const XrLoaderInitInfoPropertiesEXT initProps{
        XR_TYPE_LOADER_INIT_INFO_PROPERTIES_EXT,
        nullptr,
        1,
        properties,
    };

    xr = pfnInitializeLoaderKHR(reinterpret_cast<const XrLoaderInitInfoBaseHeaderKHR *>(&initProps));
    if (XR_FAILED(xr)) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrInitializeLoaderKHR failed with result=%1").arg(xr);
        }
        return false;
    }

    return true;
}

void KwinVr::ensureMonadoRunning()
{
    // Check if the OpenXR runtime's IPC socket exists.
    // For Monado, this is monado_comp_ipc in XDG_RUNTIME_DIR.
    const QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    const QString ipcSocket = runtimeDir + QStringLiteral("/monado_comp_ipc");

    if (QFileInfo::exists(ipcSocket)) {
        qCDebug(KWINVR) << "OpenXR runtime IPC socket found:" << ipcSocket;
        proceedWithVrActivation();
        return;
    }

    if (m_waitingForMonado) {
        return; // Already waiting
    }

    qCDebug(KWINVR) << "OpenXR runtime not running, starting monado.service...";

    // Start the runtime via systemd user service (non-blocking)
    QProcess::startDetached(QStringLiteral("systemctl"),
                            {QStringLiteral("--user"), QStringLiteral("start"), QStringLiteral("monado.service")});

    // Poll for the IPC socket to appear
    m_waitingForMonado = true;
    auto *timer = new QTimer(this);
    int *attempts = new int(0);
    connect(timer, &QTimer::timeout, this, [this, timer, attempts, ipcSocket]() {
        (*attempts)++;
        if (QFileInfo::exists(ipcSocket)) {
            qCDebug(KWINVR) << "OpenXR runtime ready after" << *attempts * 500 << "ms";
            timer->stop();
            timer->deleteLater();
            delete attempts;
            m_waitingForMonado = false;
            proceedWithVrActivation();
        } else if (*attempts >= 30) { // 15 seconds timeout
            qCWarning(KWINVR) << "Timed out waiting for OpenXR runtime";
            timer->stop();
            timer->deleteLater();
            delete attempts;
            m_waitingForMonado = false;
            showNotification(i18n("Failed to Activate VR mode"),
                             i18n("OpenXR runtime did not start in time"),
                             KNotification::CloseOnTimeout);
        }
    });
    timer->start(500);
}

void KwinVr::proceedWithVrActivation()
{
    showNotification(i18n("Starting VR mode"),
                     i18n("Standby"),
                     KNotification::Persistent);

    m_engine = new QQmlApplicationEngine(this);
    connect(m_engine, &QObject::destroyed, this, [this] {
        // Clean everything inside KWin.
        workspace()->setVrMode(false);
        KwinVrHelpers::setDmabufFormatFilterForQt(false);
        const auto windows = workspace()->windows();
        for (auto window : windows) {
            window->setVr(false);
        }

        KwinVrHelpers::setDmabufFormatFilterForQt(false);
        input()->pointer()->setPositionLimiter(nullptr);
        workspace()->setPopupBoundsResolver(nullptr);

        m_active = false;
        Q_EMIT vrActiveChanged();
    });
    // m_active will be set to false only when engine is deleted
    m_active = true;
    Q_EMIT vrActiveChanged();

    if (KWinVRConfigWrapper::instance()->xrTestEnabled()) {
        m_xrTest.start();
    } else {
        start();
    }
}

void KwinVr::setVrActive(bool active)
{
    if (active == m_active) {
        return;
    }

    if (active) {
        const QString runtimeJsonPath = KWinVRConfigWrapper::instance()->openXrRuntimeJson().trimmed();

        if (!runtimeJsonPath.isEmpty() && (!m_openXRLoaderInitialized || m_openXRLoaderRuntimePath != runtimeJsonPath)) {
            QString initError;
            if (!initOpenXRLoaderWithRuntime(runtimeJsonPath, &initError)) {
                qCWarning(KWINVR) << "OpenXR loader init failed:" << initError;
                showNotification(i18n("Failed to Activate VR mode"),
                                 i18n("OpenXR loader init failed: %1", initError),
                                 KNotification::CloseOnTimeout);
                return;
            }

            m_openXRLoaderInitialized = true;
            m_openXRLoaderRuntimePath = runtimeJsonPath;
            qCDebug(KWINVR) << "OpenXR loader initialized with runtime JSON:" << runtimeJsonPath;
        }

        // Ensure the OpenXR runtime is running before proceeding.
        // This avoids deadlocks from socket-activated startup where
        // Monado's Wayland roundtrip blocks on KWin while KWin blocks on Monado's IPC.
        ensureMonadoRunning();
    } else {
        stop();
        closeNotification();
    }
}

void KwinVr::onActivateVr(bool)
{
    qCDebug(KWINVR) << "VR mode activation triggered";
    setVrActive(!m_active);
}

void KwinVr::start()
{
    if (!m_engine) {
        return;
    }

    auto onObjectCreated = [this](QObject *obj, const QUrl &) {
        if (!obj) {
            showNotification(i18n("Failed to Activate VR mode"),
                             i18n("Failed to load QML Engine"),
                             KNotification::CloseOnTimeout);
            stop();
        } else {
            // We need to stop the test here to not let monado
            // to shutdown if IPC_EXIT_WHEN_IDLE=ON
            m_xrTest.stop();
            closeNotification();
        }
    };
    QObject::connect(m_engine, &QQmlApplicationEngine::objectCreated,
                     this, onObjectCreated, Qt::QueuedConnection);

    qputenv("QT_QUICK3D_XR_OVERLAY_PLACEMENT", QByteArray::number(KWinVRConfigWrapper::instance()->overlayPlacement()));
    qputenv("QT_QUICK3D_XR_ASYNC_RENDER", KWinVRConfigWrapper::instance()->threadedRendering() ? "1" : "0");
    qputenv("QT_QUICK3D_XR_DISABLE_MULTIVIEW", KWinVRConfigWrapper::instance()->multiview() ? "0" : "1");

    input()->pointer()->setPositionLimiter([](const QPointF &pos, const QPointF &, std::chrono::microseconds) {
        return pos;
    });

    workspace()->setPopupBoundsResolver([](Window *parent) {
        auto bounds = parent->clientGeometry();
        Window *root = parent;
        while (Window *next = root->transientFor()) {
            root = next;
            bounds = bounds.united(root->clientGeometry());
        }
        if (!root->isVr()) {
            bounds = bounds.united(workspace()->clientArea(parent->isFullScreen() ? FullScreenArea : PlacementArea, parent));
        }
        return bounds;
    });

    workspace()->setVrMode(true);
    KwinVrHelpers::setDmabufFormatFilterForQt(true);

    m_engine->loadFromModule(QStringLiteral("org.kde.kwin.vr"), QStringLiteral("Main"));
}

void KwinVr::stop()
{
    m_xrTest.stop();

    if (m_engine) {
        m_engine->deleteLater();
        m_engine = nullptr;
    }
}

void KwinVr::showNotification(const QString &title, const QString &text,
                              KNotification::NotificationFlags flags)
{
    closeNotification();
    // TODO: using graphicsreset eventId here because we do not control kwin.notifyrc
    m_notification = new KNotification("graphicsreset", flags, this);
    m_notification->setAutoDelete(false);
    m_notification->setTitle(title);
    m_notification->setText(text);
    m_notification->sendEvent();
}

void KwinVr::closeNotification()
{
    if (m_notification) {
        m_notification->close();
        m_notification->deleteLater();
        m_notification = nullptr;
    }
}

QVariantList KwinVr::leasableOutputs() const
{
    QVariantList result;
    const auto outputs = kwinApp()->outputBackend()->outputs();
    for (BackendOutput *output : outputs) {
        if (!(output->capabilities() & BackendOutput::Capability::Leasing) || output->isNonDesktop()) {
            continue;
        }
        result.append(QVariantMap{
            {QStringLiteral("name"), output->name()},
            {QStringLiteral("manufacturer"), output->manufacturer()},
            {QStringLiteral("model"), output->model()},
            {QStringLiteral("leasable"), output->isLeasable()},
            {QStringLiteral("leased"), output->isLeased() || output->isLeasePending()},
        });
    }
    return result;
}

bool KwinVr::setOutputLeasable(const QString &outputName, bool leasable)
{
    const auto outputs = kwinApp()->outputBackend()->outputs();
    for (BackendOutput *output : outputs) {
        if (output->name() == outputName) {
            OutputConfiguration config;
            config.changeSet(output)->leasable = leasable;
            auto error = Workspace::self()->applyOutputConfiguration(config);
            return error == OutputConfigurationError::None;
        }
    }
    return false;
}

void KwinVr::refreshLeases()
{
    qCDebug(KWINVR) << "refreshLeases: restarting monado and re-offering leasable outputs";

    // Restart Monado so it gets a fresh Wayland connection to this session
    QProcess::startDetached(QStringLiteral("systemctl"),
                            {QStringLiteral("--user"), QStringLiteral("restart"), QStringLiteral("monado.service")});

    // Toggle leasable off then on for all leasable outputs to force re-offer
    const auto outputs = kwinApp()->outputBackend()->outputs();
    for (BackendOutput *output : outputs) {
        if (output->isLeasable() && !output->isLeased()) {
            OutputConfiguration offConfig;
            offConfig.changeSet(output)->leasable = false;
            Workspace::self()->applyOutputConfiguration(offConfig);

            OutputConfiguration onConfig;
            onConfig.changeSet(output)->leasable = true;
            Workspace::self()->applyOutputConfiguration(onConfig);
        }
    }
}

void KwinVr::registerDBusService()
{
    // We can still activate the plugin by hotkey,
    // so DBus registration failure is not fatal.

    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.kde.kwinvr"))) {
        qCWarning(KWINVR) << "Failed to register org.kde.kwinvr dbus service";
        return;
    }

    if (!bus.registerObject(QStringLiteral("/KwinVr"), this,
                            QDBusConnection::ExportAllProperties | QDBusConnection::ExportAllSignals | QDBusConnection::ExportAllSlots)) {
        qCWarning(KWINVR) << "Failed to register /KwinVr object at session bus";
    }
}

} // namespace KWin
