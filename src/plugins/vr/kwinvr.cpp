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
#include <QDBusConnectionInterface>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QTimer>

#include "core/output.h"
#include "cursor.h"
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
        // Watchdog only applies to Monado-backed sessions
        if (!m_activeProfile || m_activeProfile->openxrRuntime != QStringLiteral("monado"))
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

    // Set up profile-driven output monitoring
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
    if (active == m_active)
        return;

    if (active) {
        // If called directly (e.g. via D-Bus from xreal-mode-watch.sh) without going
        // through activateForProfile, auto-detect the output and profile from whichever
        // output is currently in SBS mode — then re-enter via activateForProfile so
        // that KWIN_FORCE_DESKTOP_OUTPUTS, hasPhysicalPrimary, etc. are all set.
        if (!m_vrOutput) {
            for (auto *output : workspace()->outputs()) {
                auto profile = matchDisplayProfile(output);
                if (!profile)
                    continue;
                const auto mode = output->currentMode();
                if (mode && profile->isSbsMode(mode->size().width(), mode->size().height())) {
                    qWarning() << "VR: setVrActive(true) without output context — auto-detected"
                               << output->name() << "for profile" << profile->name;
                    activateForProfile(*profile, output);
                    return;
                }
            }
        }

        showNotification(QStringLiteral("Starting VR mode"),
                         QStringLiteral("Standby"),
                         KNotification::CloseOnTimeout);

        m_engine = new QQmlApplicationEngine(this);
        connect(m_engine, &QObject::destroyed, this, [this] {
            // Re-enable physical outputs that were disabled for VR mode.
            // Must run first — the virtual output is already gone at this point,
            // and restoreOutputs() re-enables the outputs we disabled in activateOutput().
            KwinVrHelpers::restoreOutputs();

            workspace()->setVrMode(false);
            KwinVrHelpers::setDmabufFormatFilterForQt(false);
            const auto windows = workspace()->windows();
            for (auto window : windows)
                window->setVr(false);
            input()->pointer()->setForcedFocusWindow(nullptr);

            m_vrOutput = nullptr;
            m_activeProfile = std::nullopt;
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
                        if (!m_active && m_vrOutput) {
                            auto profile = matchDisplayProfile(m_vrOutput);
                            if (profile)
                                activateForProfile(*profile, m_vrOutput);
                        }
                    });
                }
                return;
            }

            // No retry — check if a service-type VR should resume
            maybeRestoreServiceVr();
        });

        m_active = true;
        Q_EMIT vrActiveChanged();

        // Record Monado PID so the watchdog can detect restarts
        m_monadoPidAtVrStart = -1;
        if (m_activeProfile && m_activeProfile->openxrRuntime == QStringLiteral("monado")) {
            const QString pidFile = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                                    + QStringLiteral("/monado.pid");
            QFile pf(pidFile);
            if (pf.open(QIODevice::ReadOnly))
                m_monadoPidAtVrStart = pf.readAll().trimmed().toLongLong();
            qCInfo(KWINVR) << "VR starting with Monado PID" << m_monadoPidAtVrStart;
            m_watchdogTimer->start();
        }

        start();
    } else {
        m_retryOutput = nullptr;
        stop();
        closeNotification();
    }
}

void KwinVr::onActivateVr(bool checked)
{
    Q_UNUSED(checked)
    qCDebug(KWINVR) << "VR mode activation triggered";

    if (m_active) {
        setVrActive(false);
        return;
    }

    // Find the best output+profile to activate for.
    // Prefer an output already in SBS mode; fall back to any EDID match.
    Output *bestOutput = nullptr;
    std::optional<VrProfile> bestProfile;

    for (auto *output : workspace()->outputs()) {
        auto profile = matchDisplayProfile(output);
        if (!profile)
            continue;
        const auto mode = output->currentMode();
        if (mode && profile->isSbsMode(mode->size().width(), mode->size().height())) {
            bestOutput = output;
            bestProfile = profile;
            break; // SBS match is ideal
        }
        if (!bestOutput) {
            bestOutput = output;
            bestProfile = profile;
        }
    }

    if (bestProfile) {
        qCInfo(KWINVR) << "Manual VR activation: using profile" << bestProfile->name
                       << "on output" << (bestOutput ? bestOutput->name() : QStringLiteral("(none)"));
        activateForProfile(*bestProfile, bestOutput);
    } else {
        qCInfo(KWINVR) << "Manual VR activation: no display profile matched, activating without profile";
        setVrActive(true);
    }
}

void KwinVr::start()
{
    if (!m_engine)
        return;

    const auto onObjectCreated = [this](QObject *obj, const QUrl &) {
        if (!obj) {
            showNotification(QStringLiteral("Failed to Activate VR mode"),
                             QStringLiteral("Failed to load QML Engine"),
                             KNotification::CloseOnTimeout);
            stop();
        } else {
            m_xrTest.stop();
            closeNotification();

            qWarning() << "VR: objectCreated OK — vrOutput:" << (m_vrOutput ? m_vrOutput->name() : "(null)")
                       << "profile:" << (m_activeProfile ? m_activeProfile->name : "(none)")
                       << "detectType:" << (m_activeProfile ? (int)m_activeProfile->detectType : -1);

            // For display-type profiles (e.g. Xreal Air), steer Monado's compositor
            // window (app_id "openxr") to the physical VR output.
            // m_monadoWindowConnection stays connected for the full VR session so
            // that Monado restarts (Restart=on-failure) are handled automatically.
            if (m_vrOutput && m_activeProfile
                && m_activeProfile->detectType == VrDetectType::Display) {

                qWarning() << "VR: scanning" << workspace()->windows().size() << "windows:";
                for (auto *w : workspace()->windows())
                    qWarning() << "  window desktopFileName=" << w->desktopFileName()
                               << "caption=" << w->caption()
                               << "output=" << (w->output() ? w->output()->name() : "(null)");

                // Steer one Monado window to m_vrOutput.
                // Uses m_monadoFsConnection for the one-shot fullScreenChanged correction
                // so the persistent windowAdded watcher (m_monadoWindowConnection) is untouched.
                auto pinMonadoWindow = [this](Window *w) {
                    qWarning() << "VR: pinMonadoWindow called for" << w->desktopFileName()
                               << "output=" << (w->output() ? w->output()->name() : "(null)")
                               << "fullscreen=" << w->isFullScreen();
                    if (w->output() != m_vrOutput) {
                        const bool wasFs = w->isFullScreen();
                        if (wasFs)
                            w->setFullScreen(false);
                        w->sendToOutput(m_vrOutput);
                        if (wasFs)
                            w->setFullScreen(true);
                        w->setKeepAbove(true);
                        qWarning() << "VR: Monado window placed on"
                                   << m_vrOutput->name() << m_vrOutput->geometry();
                    }

                    if (!w->isFullScreen()) {
                        disconnect(m_monadoFsConnection);
                        m_monadoFsConnection = connect(w, &Window::fullScreenChanged,
                                                       this, [this, w] {
                            disconnect(m_monadoFsConnection);
                            qWarning() << "VR: fullScreenChanged — fullscreen=" << w->isFullScreen()
                                       << "output=" << (w->output() ? w->output()->name() : "(null)");
                            if (!w->isFullScreen() || !m_vrOutput
                                || w->output() == m_vrOutput)
                                return;
                            qWarning() << "VR: correcting Monado to" << m_vrOutput->name();
                            w->setFullScreen(false);
                            w->sendToOutput(m_vrOutput);
                            w->setFullScreen(true);
                        });
                    }
                };

                // Pin any already-present openxr window
                for (auto *w : workspace()->windows()) {
                    if (w->desktopFileName() != QLatin1String("openxr"))
                        continue;
                    pinMonadoWindow(w);
                    break;
                }

                // Persistent watcher: handles Monado restarts throughout the VR session.
                // Does NOT disconnect on match — keeps watching for future "openxr" windows.
                qWarning() << "VR: installing persistent windowAdded watcher for openxr";
                m_monadoWindowConnection = connect(
                    workspace(), &Workspace::windowAdded,
                    this, [this, pinMonadoWindow](Window *w) {
                    qWarning() << "VR: windowAdded desktopFileName=" << w->desktopFileName()
                               << "caption=" << w->caption();
                    if (w->desktopFileName() != QLatin1String("openxr"))
                        return;
                    pinMonadoWindow(w);
                });
            }
        }
    };
    QObject::connect(m_engine, &QQmlApplicationEngine::objectCreated,
                     this, onObjectCreated, Qt::QueuedConnection);

    qputenv("QT_QUICK3D_XR_OVERLAY_PLACEMENT",
            QByteArray::number(KWinVRConfigWrapper::instance()->overlayPlacement()));

    workspace()->setVrMode(true);
    Cursors::self()->hideCursor();
    m_cursorHidden = true;
    KwinVrHelpers::setDmabufFormatFilterForQt(true);

    // Force Vulkan for the XR subsystem; KWin uses OpenGL for compositing but
    // XrGraphicsBindingOpenGLWaylandKHR is unsupported by Monado.
    const auto savedApi = QQuickWindow::graphicsApi();
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);

    m_engine->rootContext()->setContextProperty("kwinVrBridge", &m_vrbridge);
    m_engine->loadFromModule(QStringLiteral("org.kde.kwin.vr"), QStringLiteral("Main"));

    QQuickWindow::setGraphicsApi(savedApi);
}

void KwinVr::stop()
{
    disconnect(m_monadoWindowConnection);
    disconnect(m_monadoFsConnection);
    m_xrTest.stop();
    if (m_cursorHidden) {
        Cursors::self()->showCursor();
        m_cursorHidden = false;
    }
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
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.kde.kwinvr"))) {
        qCWarning(KWINVR) << "Failed to register org.kde.kwinvr dbus service";
        return;
    }
    if (!bus.registerObject(QStringLiteral("/KwinVr"), this,
                            QDBusConnection::ExportAllProperties
                                | QDBusConnection::ExportAllSignals
                                | QDBusConnection::ExportScriptableInvokables)) {
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

    // Set KWIN_FORCE_DESKTOP_OUTPUTS for profiles that provide a connector hint.
    // This allows KWin to expose headsets whose EDID has the non-desktop bit set
    // (e.g. Samsung Odyssey+) as regular Wayland outputs.
    QStringList forceDesktop = qEnvironmentVariable("KWIN_FORCE_DESKTOP_OUTPUTS")
                                   .split(u',', Qt::SkipEmptyParts);
    for (const auto &profile : std::as_const(m_profiles)) {
        if (profile.detectType == VrDetectType::Display && !profile.connectorHint.isEmpty()
            && !forceDesktop.contains(profile.connectorHint))
            forceDesktop.append(profile.connectorHint);
    }
    if (!forceDesktop.isEmpty()) {
        qputenv("KWIN_FORCE_DESKTOP_OUTPUTS", forceDesktop.join(u',').toUtf8());
        qCInfo(KWINVR) << "KWIN_FORCE_DESKTOP_OUTPUTS set to:" << forceDesktop.join(u',');
    }

    // Watch service-type profiles on the session D-Bus
    setupServiceWatcher();

    // Check outputs already present at plugin load time
    const auto outputs = workspace()->outputs();
    for (auto *output : outputs)
        scheduleOutputCheck(output, /*isHotPlug=*/false);

    connect(workspace(), &Workspace::outputAdded, this, &KwinVr::onOutputAdded);
    connect(workspace(), &Workspace::outputRemoved, this, &KwinVr::onOutputRemoved);
}

void KwinVr::setupServiceWatcher()
{
    QStringList serviceNames;
    for (const auto &profile : std::as_const(m_profiles)) {
        if (profile.detectType == VrDetectType::Service && !profile.detectService.isEmpty())
            serviceNames.append(profile.detectService);
    }
    if (serviceNames.isEmpty())
        return;

    m_serviceWatcher = new QDBusServiceWatcher(this);
    m_serviceWatcher->setConnection(QDBusConnection::sessionBus());
    m_serviceWatcher->setWatchMode(QDBusServiceWatcher::WatchForRegistration
                                   | QDBusServiceWatcher::WatchForUnregistration);
    for (const auto &svc : serviceNames)
        m_serviceWatcher->addWatchedService(svc);

    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, &KwinVr::onServiceRegistered);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &KwinVr::onServiceUnregistered);

    // Check whether any watched service is already running
    auto iface = QDBusConnection::sessionBus().interface();
    for (const auto &svc : serviceNames) {
        if (iface && iface->isServiceRegistered(svc).value())
            onServiceRegistered(svc);
    }
}

void KwinVr::onServiceRegistered(const QString &service)
{
    qCInfo(KWINVR) << "VR service appeared on D-Bus:" << service;
    if (m_active) {
        qCInfo(KWINVR) << "VR already active (display takes priority) — ignoring service";
        return;
    }

    for (const auto &profile : std::as_const(m_profiles)) {
        if (profile.detectType != VrDetectType::Service || profile.detectService != service)
            continue;
        qCInfo(KWINVR) << "Activating VR for service profile:" << profile.name;
        activateForProfile(profile, nullptr);
        return;
    }
}

void KwinVr::onServiceUnregistered(const QString &service)
{
    qCInfo(KWINVR) << "VR service left D-Bus:" << service;
    if (!m_active || !m_activeProfile)
        return;
    if (m_activeProfile->detectType == VrDetectType::Service
        && m_activeProfile->detectService == service) {
        qCInfo(KWINVR) << "Service-triggered VR service gone — deactivating";
        setVrActive(false);
    }
}

void KwinVr::maybeRestoreServiceVr()
{
    // Called after display-triggered VR ends. If a service-type profile's D-Bus
    // service is still registered, resume service VR.
    auto iface = QDBusConnection::sessionBus().interface();
    if (!iface)
        return;
    for (const auto &profile : std::as_const(m_profiles)) {
        if (profile.detectType != VrDetectType::Service)
            continue;
        if (iface->isServiceRegistered(profile.detectService).value()) {
            qCInfo(KWINVR) << "Restoring service VR for" << profile.name
                           << "after display session ended";
            QTimer::singleShot(1000, this, [this, profile] {
                if (!m_active)
                    activateForProfile(profile, nullptr);
            });
            return;
        }
    }
}

void KwinVr::activateForProfile(const VrProfile &profile, Output *output)
{
    m_activeProfile = profile;
    m_vrOutput = output;

    // Determine if a physical monitor was primary before VR activated.
    // QML uses this to drive immersive mode: immersive = !hasPhysicalPrimary.
    const auto order = workspace()->outputOrder();
    Output *primaryBefore = order.isEmpty() ? nullptr : order.first();
    bool physicalPrimary = primaryBefore
        && primaryBefore != output // not the headset itself
        && !primaryBefore->name().startsWith(QLatin1String("Virtual"));
    m_vrbridge.setHasPhysicalPrimary(physicalPrimary);

    // For display-type profiles, dynamically register the matched output as the
    // headset display in KWIN_FORCE_DESKTOP_OUTPUTS. This is read by activateOutput()
    // (to move the headset off-screen while Virtual-T is primary) and by OutputModel
    // (to exclude the headset from pseudo-mirror list). Set before the QML engine
    // loads so both consumers see the correct value.
    if (output && profile.detectType == VrDetectType::Display) {
        qputenv("KWIN_FORCE_DESKTOP_OUTPUTS", output->name().toUtf8());
        qCInfo(KWINVR) << "VR: headset output registered as" << output->name();
    } else if (profile.detectType != VrDetectType::Display) {
        // Only clear the env var for non-display profiles.
        // For display profiles with a null output (output object temporarily
        // unavailable during mode transition), preserve whatever was already set
        // by requestActivateProfile() so OutputModel excludes the headset.
        qunsetenv("KWIN_FORCE_DESKTOP_OUTPUTS");
    }

    // Apply profile display dimensions to the VR config so the QML virtual
    // screen is created at the correct resolution for this headset.
    if (profile.width > 0 || profile.height > 0) {
        auto *cfg = KWinVRConfigWrapper::instance();
        if (profile.width > 0)
            cfg->setWidth(profile.width);
        if (profile.height > 0)
            cfg->setHeight(profile.height);
        if (profile.refresh > 0)
            cfg->setRefreshrate(profile.refresh);
        if (profile.scale > 0)
            cfg->setScale(qRound(profile.scale));
        qCInfo(KWINVR) << "VR config: virtual screen set to"
                       << cfg->width() << "x" << cfg->height()
                       << "@" << cfg->refreshrate() << "Hz, scale" << cfg->scale();
    }

    if (profile.openxrRuntime == QStringLiteral("monado")) {
        const QString monadoSocket = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
            + QStringLiteral("/monado_comp_ipc");
        if (!QFile::exists(monadoSocket)) {
            qCInfo(KWINVR) << "Monado IPC socket not found — starting monado.service";
            QProcess::startDetached(QStringLiteral("systemctl"),
                                    {QStringLiteral("--user"), QStringLiteral("start"),
                                     QStringLiteral("monado.service")});
            QTimer::singleShot(3000, this, [this] {
                if (!m_active && (m_vrOutput || (m_activeProfile && m_activeProfile->detectType == VrDetectType::Service)))
                    setVrActive(true);
            });
            return;
        }
    }

    setVrActive(true);
}

std::optional<VrProfile> KwinVr::matchDisplayProfile(Output *output) const
{
    const QString outputName = output->name();
    const QString edidName = VrProfileLoader::readEdidMonitorName(outputName);

    if (edidName.isEmpty()) {
        qCDebug(KWINVR) << "No EDID monitor name available for output" << outputName;
        return std::nullopt;
    }

    for (const auto &profile : m_profiles) {
        if (profile.detectType != VrDetectType::Display)
            continue;
        if (!edidName.contains(profile.edidName, Qt::CaseInsensitive))
            continue;
        if (!VrProfileLoader::isUsbDevicePresent(profile.usbId))
            continue;
        return profile;
    }
    return std::nullopt;
}

bool KwinVr::isOutputInSbsMode(Output *output) const
{
    if (!output)
        return false;
    auto profile = matchDisplayProfile(output);
    if (!profile || profile->isAutoStart())
        return false;
    const auto mode = output->currentMode();
    return mode && profile->isSbsMode(mode->size().width(), mode->size().height());
}

void KwinVr::onOutputAdded(Output *output)
{
    scheduleOutputCheck(output, /*isHotPlug=*/true);
}

void KwinVr::onOutputRemoved(Output *output)
{
    if (m_watchedOutputs.remove(output))
        output->disconnect(this);

    if (m_vrOutput == output && m_active) {
        qCInfo(KWINVR) << "VR output" << output->name() << "removed — deactivating VR";
        setVrActive(false);
    }
}

void KwinVr::scheduleOutputCheck(Output *output, bool isHotPlug)
{
    auto profile = matchDisplayProfile(output);
    if (!profile) {
        qCDebug(KWINVR) << "No VR profile matched for output" << output->name();
        return;
    }

    qCInfo(KWINVR) << "Output" << output->name() << "matched profile" << profile->name
                   << "(autoStart:" << profile->isAutoStart() << ", hotPlug:" << isHotPlug << ")";

    if (!profile->isAutoStart()) {
        // SBS-triggered device (e.g. Xreal Air): watch for mode change to SBS resolution
        watchOutputModes(output);
        return;
    }

    // Auto-start device (e.g. Samsung Odyssey+): activate after a short delay.
    // Boot-time connections need more time than hot-plug reconnects.
    const int delayMs = isHotPlug ? 3000 : 15000;
    qCInfo(KWINVR) << "Scheduling VR auto-start for" << profile->name << "in" << delayMs << "ms";

    QTimer::singleShot(delayMs, this, [this, output, profile = *profile] {
        if (m_active)
            return;
        if (!workspace()->outputs().contains(output)) {
            qCInfo(KWINVR) << "Output for profile" << profile.name << "gone before auto-start";
            return;
        }
        qCInfo(KWINVR) << "Auto-starting VR for" << profile.name << "on" << output->name();
        activateForProfile(profile, output);
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

    // Check current mode immediately in case SBS is already active at startup
    checkOutputMode(output);
}

void KwinVr::checkOutputMode(Output *output)
{
    auto profile = matchDisplayProfile(output);
    if (!profile || profile->isAutoStart())
        return;

    const auto mode = output->currentMode();
    if (!mode)
        return;

    const int w = mode->size().width();
    const int h = mode->size().height();
    const bool inSbs = profile->isSbsMode(w, h);

    if (inSbs && !m_active) {
        qCInfo(KWINVR) << "SBS mode detected on" << output->name()
                       << "(" << w << "x" << h << ")"
                       << "— activating VR for" << profile->name;
        // If the custodian service is running, it owns the activation sequence
        // (HID init, Monado start, socket wait). Defer to requestActivateProfile()
        // instead of racing against it.
        auto *iface = QDBusConnection::sessionBus().interface();
        if (iface && iface->isServiceRegistered(QStringLiteral("org.kde.kwinvr.Custodian")).value()) {
            qCInfo(KWINVR) << "Custodian present — deferring activation to requestActivateProfile";
            return;
        }
        activateForProfile(*profile, output);
    } else if (inSbs && m_active && m_vrOutput == nullptr
               && m_activeProfile && m_activeProfile->detectType == VrDetectType::Service) {
        // Display SBS detected while service VR (WiVRn) is active — preempt it.
        qCInfo(KWINVR) << "Preempting service VR with display VR on" << output->name();
        m_retryOutput = nullptr; // don't retry service
        setVrActive(false);
        // activateForProfile is called when the engine destroyed signal fires
        // via maybeRestoreServiceVr... except we want display VR, not service.
        // Schedule it directly.
        QTimer::singleShot(500, this, [this, output, profile = *profile] {
            if (!m_active)
                activateForProfile(profile, output);
        });
    } else if (!inSbs && m_active && m_vrOutput == output) {
        qCInfo(KWINVR) << "SBS mode ended on" << output->name()
                       << "(" << w << "x" << h << ")"
                       << "— deactivating VR";
        setVrActive(false);
    }
}

void KwinVr::requestActivateProfile(const QString &profileName, const QString &outputName)
{
    if (m_active) {
        qCDebug(KWINVR) << "requestActivateProfile ignored — VR already active";
        return;
    }

    qCInfo(KWINVR) << "Custodian requests activation: profile" << profileName
                   << "output" << outputName;

    // Pre-set KWIN_FORCE_DESKTOP_OUTPUTS from the output name string before
    // doing the output object lookup. The output object may be temporarily
    // absent during a mode transition (EDID change), but the name is known.
    // This ensures OutputModel sees the correct exclusion even if activateForProfile()
    // receives a null output pointer.
    if (!outputName.isEmpty()) {
        for (const auto &p : m_profiles) {
            if (p.name == profileName && p.detectType == VrDetectType::Display) {
                qputenv("KWIN_FORCE_DESKTOP_OUTPUTS", outputName.toUtf8());
                qCInfo(KWINVR) << "Pre-set KWIN_FORCE_DESKTOP_OUTPUTS =" << outputName;
                break;
            }
        }
    }

    // Look up the profile by name
    std::optional<VrProfile> profile;
    for (const auto &p : m_profiles) {
        if (p.name == profileName) {
            profile = p;
            break;
        }
    }
    if (!profile && !profileName.isEmpty()) {
        qCWarning(KWINVR) << "requestActivateProfile: unknown profile" << profileName
                          << "— activating without profile context";
    }

    // Look up the output by name
    Output *output = nullptr;
    if (!outputName.isEmpty()) {
        for (auto *o : workspace()->outputs()) {
            if (o->name() == outputName) {
                output = o;
                break;
            }
        }
        if (!output)
            qCWarning(KWINVR) << "requestActivateProfile: output" << outputName << "not found";
    }

    if (profile) {
        activateForProfile(*profile, output);
    } else {
        // No profile context: fall back to generic activation
        m_vrOutput = output;
        setVrActive(true);
    }
}

void KwinVr::requestDeactivate()
{
    qCInfo(KWINVR) << "Custodian requests deactivation";
    setVrActive(false);
}

void KwinVr::notifyLinkDegraded(const QString &connector, int lanes, const QString &rateHex)
{
    qCWarning(KWINVR) << "DP link degraded on" << connector
                      << "— current:" << lanes << "lanes @" << rateHex;
    showNotification(
        QStringLiteral("Display Link Degraded"),
        QStringLiteral("Connector %1: link trained at %2 lane(s) @ %3.\n"
                       "VR SBS mode may not be achievable. Try reconnecting the display.")
            .arg(connector)
            .arg(lanes)
            .arg(rateHex),
        KNotification::CloseOnTimeout);
}
