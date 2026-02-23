/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvr.h"

#include <KGlobalAccel>
#include <KLocalizedString>

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QFile>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>

#include "core/output.h"
#include "input.h"
#include "pointer_input.h"
#include "window.h"
#include "workspace.h"

#include "kwinvr_logging.h"
#include "kwinvrconfigwrapper.h"
#include "kwinvrhelpers.h"
#include "kwinvrshortcuts.h"
#include "vrprofile.h"

using namespace KWin;

KwinVr::KwinVr()
{
    auto config = KWinVRConfigWrapper::instance();
    m_watcher = KConfigWatcher::create(config->sharedConfig());
    connect(m_watcher.data(), &KConfigWatcher::configChanged, config, &KWinVRConfigWrapper::load);

    // Register shortcuts at plugin load (before VR activation)
    KWinVrShortcuts::instance();

    registerDBusService();

    auto cycleAction = new QAction(this);
    connect(cycleAction, &QAction::triggered, this, &KwinVr::onActivateVr);
    cycleAction->setObjectName(QStringLiteral("Activate VR Mode"));
    cycleAction->setText(i18nc("@action Activate VR Mode", "Activate VR Mode"));
    KGlobalAccel::self()->setDefaultShortcut(cycleAction, {{Qt::CTRL | Qt::META | Qt::Key_J}});
    KGlobalAccel::self()->setShortcut(cycleAction, {});

    // Watchdog: every 5s while VR is active, compare the running Monado PID to the
    // one we recorded when the session started. If it changed, Monado restarted and
    // the XR IPC connection is broken (Qt's XrView does not detect this itself).
    m_watchdogTimer = new QTimer(this);
    m_watchdogTimer->setInterval(5000);
    connect(m_watchdogTimer, &QTimer::timeout, this, [this] {
        if (!m_active)
            return;
        const QString pidFile = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                                + QStringLiteral("/monado.pid");
        QFile pf(pidFile);
        if (!pf.open(QIODevice::ReadOnly))
            return;
        const qint64 currentPid = pf.readAll().trimmed().toLongLong();
        if (m_monadoPidAtVrStart > 0 && currentPid != m_monadoPidAtVrStart) {
            qCWarning(KWINVR) << "Monado restarted (old PID:" << m_monadoPidAtVrStart
                              << "new PID:" << currentPid << "), XR session is broken — stopping";
            if (m_vrOutput && isOutputInSbsMode(m_vrOutput)) {
                qCInfo(KWINVR) << "Output still in SBS mode, scheduling retry";
                m_retryOutput = m_vrOutput;
            }
            stop();
        }
    });

    connect(&m_vrbridge, &KwinVrBridge::xrFailed, this, [this](const QString &errorString) {
        qCWarning(KWINVR) << "XR failed signal received:" << errorString;
        showNotification(QStringLiteral("Failed to Activate VR mode"),
                         QStringLiteral("error: ") + errorString,
                         KNotification::CloseOnTimeout);
        // Retry if the triggering output is still in SBS mode
        if (m_vrOutput && isOutputInSbsMode(m_vrOutput)) {
            qCInfo(KWINVR) << "Output still in SBS mode after XR failure, scheduling retry";
            m_retryOutput = m_vrOutput;
        }
        stop();
    }, Qt::QueuedConnection);

    connect(&m_xrTest, &OpenXRTest::sessionResult, this, [this](bool success, const QString &message) {
        qCWarning(KWINVR) << "OpenXR test result:" << success << "message:" << message;
        if (success) {
            start();
        } else {
            showNotification(QStringLiteral("Failed to Activate VR mode"),
                             QStringLiteral("Test Failed: ") + message,
                             KNotification::CloseOnTimeout);
            stop();
        }
    }, Qt::QueuedConnection);

    // Set up profile-driven output monitoring (replaces blind 15s autoStart timer)
    setupOutputMonitoring();
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

void KwinVr::setVrActive(bool active)
{
    if (active == m_active) {
        return;
    }

    if (active) {
        showNotification(QStringLiteral("Starting VR mode"),
                         QStringLiteral("Standby"),
                         KNotification::Persistent);

        m_engine = new QQmlApplicationEngine(this);
        connect(m_engine, &QObject::destroyed, this, [this] {
            /* Clean everything inside KWin
             * Doing it here to make sure no stuff would change these flags
             * and we can safely return to 2D mode */
            workspace()->setVrMode(false);
            KwinVrHelpers::setDmabufFormatFilterForQt(false);
            const auto windows = workspace()->windows();
            for (auto window : windows) {
                window->setVr(false);
            }
            input()->pointer()->setForcedFocusWindow(nullptr);

            m_vrOutput = nullptr;
            m_active = false;
            Q_EMIT vrActiveChanged();

            // If flagged for retry (watchdog or xrFailed), restart VR after a delay
            if (m_retryOutput) {
                Output *output = m_retryOutput;
                m_retryOutput = nullptr;
                if (workspace()->outputs().contains(output)) {
                    qCInfo(KWINVR) << "Retrying VR on" << output->name() << "in 3s";
                    m_vrOutput = output;
                    QTimer::singleShot(3000, this, [this] {
                        if (!m_active && m_vrOutput)
                            setVrActive(true);
                    });
                }
            }
        });
        /* m_active will be set to false only when engine is deleted */
        m_active = true;
        Q_EMIT vrActiveChanged();

        // Record Monado PID so the watchdog can detect restarts
        m_monadoPidAtVrStart = -1;
        {
            const QString pidFile = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                                    + QStringLiteral("/monado.pid");
            QFile pf(pidFile);
            if (pf.open(QIODevice::ReadOnly))
                m_monadoPidAtVrStart = pf.readAll().trimmed().toLongLong();
        }
        qCInfo(KWINVR) << "VR starting with Monado PID" << m_monadoPidAtVrStart;
        // Start PID-based watchdog (repeating every 5s)
        m_watchdogTimer->start();

        // XR test disabled - go straight to start
        start();
    } else {
        // Cancel any pending retry before stopping
        m_retryOutput = nullptr;
        stop();
        closeNotification();
    }
}

void KwinVr::onActivateVr(bool checked)
{
    Q_UNUSED(checked)
    qCDebug(KWINVR) << "VR mode activation triggered";
    setVrActive(!m_active);
}

void KwinVr::start()
{
    if (!m_engine)
        return;

    const QUrl url(QStringLiteral("qrc:/org.kde.kwin.vr/qml/Main.qml"));
    auto onObjectCreated = [url, this](QObject *obj, const QUrl &objUrl) {
        // if (url != objUrl) {
        //     return;
        // }

        if (!obj) {
            showNotification(QStringLiteral("Failed to Activate VR mode"),
                             QStringLiteral("Failed to load QML Engine"),
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

    workspace()->setVrMode(true);
    KwinVrHelpers::setDmabufFormatFilterForQt(true);

    // Force Vulkan rendering for the XR subsystem. Qt6Quick3DXr selects
    // its graphics binding based on QQuickWindow::graphicsApi(). KWin uses
    // OpenGL for compositing, but the OpenGL Wayland binding
    // (XrGraphicsBindingOpenGLWaylandKHR) is not supported by Monado.
    // Vulkan bindings work universally. The XR code creates its own
    // isolated QQuickRenderControl, so this doesn't affect KWin's compositor.
    const auto savedApi = QQuickWindow::graphicsApi();
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);

    m_engine->rootContext()->setContextProperty("kwinVrBridge", &m_vrbridge);
    m_engine->loadFromModule(QStringLiteral("org.kde.kwin.vr"), QStringLiteral("Main"));
    // m_engine->load(url);

    // Restore the original API so other QQuickWindows (effects, etc.) are
    // not affected.
    QQuickWindow::setGraphicsApi(savedApi);
}

void KwinVr::stop()
{
    m_xrTest.stop();
    KwinVrHelpers::setDmabufFormatFilterForQt(false);
    m_watchdogTimer->stop();

    if (m_engine) {
        m_engine->deleteLater();
        m_engine = nullptr;
    }
}

void KwinVr::showNotification(const QString &title, const QString &text,
                              KNotification::NotificationFlags flags)
{
    closeNotification();
    // TODO: using graphicsreset eventId here because we do not control kwin.notifyrc :(
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

void KwinVr::registerDBusService()
{
    /* We can stil activate the plugin by hotkey,
     * so DBus registration failure is not fatal. */

    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.kde.kwinvr"))) {
        qCWarning(KWINVR) << "Failed to register org.kde.kwinvr dbus service";
        return;
    }

    if (!bus.registerObject(QStringLiteral("/KwinVr"), this,
                            QDBusConnection::ExportAllProperties | QDBusConnection::ExportAllSignals)) {
        qCWarning(KWINVR) << "Failed to register /KwinVr object at session bus";
    }
}

void KwinVr::setupOutputMonitoring()
{
    m_profiles = VrProfileLoader::loadProfiles();
    if (m_profiles.isEmpty()) {
        qCInfo(KWINVR) << "No VR profiles found, output monitoring disabled";
        return;
    }

    // If Monado is already running from a previous KWin session, its Wayland surface
    // is connected to the old (dead) KWin, causing VK_ERROR_SURFACE_LOST_KHR when
    // a new VR session starts. Restart Monado now to give it a fresh connection.
    const QString monadoSocket = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                                 + QStringLiteral("/monado_comp_ipc");
    if (QFile::exists(monadoSocket)) {
        qCInfo(KWINVR) << "Monado already running at KWin start — restarting for fresh Wayland connection";
        QProcess::startDetached(QStringLiteral("systemctl"),
                                {QStringLiteral("--user"), QStringLiteral("restart"),
                                 QStringLiteral("monado.service")});
    }

    // Ensure KWIN_FORCE_DESKTOP_OUTPUTS covers all profile connectors.
    // This matters for headsets whose EDID has non-desktop=1 (e.g. Samsung Odyssey+):
    // KWin checks this env var in DrmConnector::isNonDesktop() on every HPD event,
    // so setting it here covers hot-plug even if the headset wasn't connected at boot.
    QStringList forceDesktop = qEnvironmentVariable("KWIN_FORCE_DESKTOP_OUTPUTS")
                                   .split(u',', Qt::SkipEmptyParts);
    for (const auto &profile : std::as_const(m_profiles)) {
        if (!forceDesktop.contains(profile.connectorName))
            forceDesktop.append(profile.connectorName);
    }
    qputenv("KWIN_FORCE_DESKTOP_OUTPUTS", forceDesktop.join(u',').toUtf8());
    qCInfo(KWINVR) << "KWIN_FORCE_DESKTOP_OUTPUTS set to:" << forceDesktop.join(u',');

    // Check outputs already present (e.g. Samsung plugged in at boot)
    const auto outputs = workspace()->outputs();
    for (auto *output : outputs)
        scheduleOutputCheck(output, /*isHotPlug=*/false);

    connect(workspace(), &Workspace::outputAdded, this, &KwinVr::onOutputAdded);
    connect(workspace(), &Workspace::outputRemoved, this, &KwinVr::onOutputRemoved);
}

bool KwinVr::isOutputInSbsMode(Output *output) const
{
    if (!output)
        return false;
    auto profile = matchProfile(output);
    if (!profile || profile->autoStart)
        return false;
    const auto mode = output->currentMode();
    return mode && profile->isSbsMode(mode->size().width());
}

std::optional<VrProfile> KwinVr::matchProfile(Output *output) const
{
    const QString name = output->name();
    for (const auto &profile : m_profiles) {
        if (profile.connectorName != name)
            continue;
        if (!VrProfileLoader::isUsbDevicePresent(profile.usbId))
            continue;
        return profile;
    }
    return std::nullopt;
}

void KwinVr::onOutputAdded(Output *output)
{
    scheduleOutputCheck(output, /*isHotPlug=*/true);
}

void KwinVr::onOutputRemoved(Output *output)
{
    // Disconnect mode-change watcher
    if (m_watchedOutputs.remove(output))
        output->disconnect(this);

    // Deactivate VR if this was the triggering output
    if (m_vrOutput == output && m_active) {
        qCInfo(KWINVR) << "VR output" << output->name() << "removed, deactivating VR";
        setVrActive(false);
    }
}

void KwinVr::scheduleOutputCheck(Output *output, bool isHotPlug)
{
    auto profile = matchProfile(output);
    if (!profile) {
        qCDebug(KWINVR) << "No VR profile matched for output" << output->name();
        return;
    }

    qCInfo(KWINVR) << "Output" << output->name() << "matched profile" << profile->name
                   << "(autoStart:" << profile->autoStart << ", hotPlug:" << isHotPlug << ")";

    if (!profile->autoStart) {
        // Mode-triggered device (e.g. Xreal Air): watch for SBS mode change
        watchOutputModes(output);
        return;
    }

    // autoStart device (e.g. Samsung Odyssey+): activate after a short delay.
    // The delay gives Monado time to finish initialising after the headset is detected.
    // Boot-time connections need more time than hot-plug reconnects.
    const int delayMs = isHotPlug ? 3000 : 15000;
    qCInfo(KWINVR) << "Scheduling VR auto-start for" << profile->name << "in" << delayMs << "ms";

    QTimer::singleShot(delayMs, this, [this, output, profileName = profile->name] {
        if (m_active)
            return; // already in VR
        if (!workspace()->outputs().contains(output)) {
            qCInfo(KWINVR) << "Output for profile" << profileName << "gone before auto-start";
            return;
        }
        qCInfo(KWINVR) << "Auto-starting VR for" << profileName << "on" << output->name();
        m_vrOutput = output;
        setVrActive(true);
    });
}

void KwinVr::watchOutputModes(Output *output)
{
    if (m_watchedOutputs.contains(output))
        return;

    m_watchedOutputs.insert(output);
    connect(output, &Output::currentModeChanged, this, [this, output] {
        checkOutputMode(output);
    });

    // Check current mode immediately in case we started with SBS already active
    checkOutputMode(output);
}

void KwinVr::checkOutputMode(Output *output)
{
    auto profile = matchProfile(output);
    if (!profile || profile->autoStart)
        return;

    const auto mode = output->currentMode();
    if (!mode)
        return;

    const bool inSbs = profile->isSbsMode(mode->size().width());

    if (inSbs && !m_active) {
        qCInfo(KWINVR) << "SBS mode detected on" << output->name()
                       << "(" << mode->size().width() << "x" << mode->size().height() << ")"
                       << "— activating VR for" << profile->name;
        m_vrOutput = output;
        // Ensure Monado is running before starting XR. If it was explicitly
        // stopped (e.g. by a previous stop_vr script call), start it back up
        // and give it 2s to initialise before we try xrCreateInstance.
        const QString monadoSocket = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                                     + QStringLiteral("/monado_comp_ipc");
        if (!QFile::exists(monadoSocket)) {
            qCWarning(KWINVR) << "Monado IPC socket not found, starting monado.service...";
            QProcess::startDetached(QStringLiteral("systemctl"),
                                    {QStringLiteral("--user"), QStringLiteral("start"),
                                     QStringLiteral("monado.service")});
            QTimer::singleShot(3000, this, [this] {
                if (m_vrOutput && !m_active)
                    setVrActive(true);
            });
            return;
        }
        setVrActive(true);
    } else if (!inSbs && m_active && m_vrOutput == output) {
        qCInfo(KWINVR) << "SBS mode ended on" << output->name()
                       << "(" << mode->size().width() << "x" << mode->size().height() << ")"
                       << "— deactivating VR";
        setVrActive(false);
    }
}
