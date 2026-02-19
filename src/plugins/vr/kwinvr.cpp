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
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

#include "input.h"
#include "pointer_input.h"
#include "window.h"
#include "workspace.h"

#include "kwinvr_logging.h"
#include "kwinvrconfigwrapper.h"
#include "kwinvrhelpers.h"
#include "kwinvrshortcuts.h"

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

    connect(&m_vrbridge, &KwinVrBridge::xrFailed, this, [this](const QString &errorString) {
        qCWarning(KWINVR) << "XR failed signal received:" << errorString;
        showNotification(QStringLiteral("Failed to Activate VR mode"),
                         QStringLiteral("error: ") + errorString,
                         KNotification::CloseOnTimeout);
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

    auto *cfg = KWinVRConfigWrapper::instance();
    cfg->load();
    qWarning() << "KwinVr: autoStart =" << cfg->autoStart()
               << "width =" << cfg->width()
               << "height =" << cfg->height();
    if (cfg->autoStart()) {
        QTimer::singleShot(15000, this, [this] {
            if (!m_active) {
                qWarning() << "KwinVr: Auto-starting VR mode now";
                setVrActive(true);
            }
        });
    }
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

            m_active = false;
            Q_EMIT vrActiveChanged();
        });
        /* m_active will be set to false only when engine is deleted */
        m_active = true;
        Q_EMIT vrActiveChanged();

        // XR test disabled - go straight to start
        start();
    } else {
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
