/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "custodian.h"
#include "custodian_logging.h"
#include "hidinit.h"
#include "udevmonitor.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>

#include <cerrno>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h> // getuid(), close()

// ─── Constants ────────────────────────────────────────────────────────────────

static const QString kPluginService = QStringLiteral("org.kde.kwinvr");
static const QString kPluginObject = QStringLiteral("/KwinVr");
static const QString kPluginInterface = QStringLiteral("org.kde.kwinvr");
static const QString kCustodianService = QStringLiteral("org.kde.kwinvr.Custodian");
static const QString kCustodianObject = QStringLiteral("/Custodian");
static const QString kProfileDirectory = QStringLiteral("/etc/vr-profiles.d");
static const QString kSystemdService = QStringLiteral("org.freedesktop.systemd1");
static const QString kSystemdObject = QStringLiteral("/org/freedesktop/systemd1");
static const QString kSystemdManager = QStringLiteral("org.freedesktop.systemd1.Manager");
static const QString kSystemdUnit = QStringLiteral("org.freedesktop.systemd1.Unit");
static const QString kDBusProperties = QStringLiteral("org.freedesktop.DBus.Properties");

// ─── Construction ─────────────────────────────────────────────────────────────

Custodian::Custodian(QObject *parent)
    : QObject(parent)
{
}

Custodian::~Custodian()
{
}

bool Custodian::start()
{
    m_udev = new UdevMonitor(this);
    m_hidInit = new HidInit(this);

    reloadProfiles();
    setupProfileWatcher(kProfileDirectory);

    if (!m_udev->start()) {
        qCWarning(KWINVRCUSTODIAN) << "udev monitor failed to start — hotplug events will not be received";
        // Not fatal: we can still respond to D-Bus triggers and manual activation
    } else {
        connect(m_udev, &UdevMonitor::drmConnectorChanged,
                this, &Custodian::onDrmConnectorChanged);
        connect(m_udev, &UdevMonitor::drmRescanNeeded,
                this, &Custodian::scanConnectors);
        connect(m_udev, &UdevMonitor::usbDeviceAdded,
                this, &Custodian::onUsbDeviceAdded);
        connect(m_udev, &UdevMonitor::usbDeviceRemoved,
                this, &Custodian::onUsbDeviceRemoved);
    }

    registerDBusService();
    setupPluginWatcher();
    setupRuntimeWatcher();

    // Check hardware that is already present when we start.
    // Scan connectors first: if the display is already in SBS mode, VR activates
    // (m_active = true) before scanUsbDevices() runs, so we skip the 2D init
    // that would otherwise undo the SBS mode and cause a USB disconnect.
    scanConnectors(); // activates VR if already in SBS mode
    scanUsbDevices(); // sends 2D HID init only if VR is not already active

    qCInfo(KWINVRCUSTODIAN) << "Custodian started with" << m_profiles.size() << "profile(s)";
    return true;
}

// ─── Profile management ───────────────────────────────────────────────────────

void Custodian::reloadProfiles()
{
    m_profiles = CustodianProfileLoader::loadProfiles(kProfileDirectory);
    setupRuntimeWatcher();
}

void Custodian::setupProfileWatcher(const QString &directory)
{
    m_profileWatcher = new QFileSystemWatcher({directory}, this);
    connect(m_profileWatcher, &QFileSystemWatcher::directoryChanged,
            this, [this] {
        qCInfo(KWINVRCUSTODIAN) << "Profile directory changed, reloading profiles";
        reloadProfiles();
    });
}

// ─── Startup USB device scan ──────────────────────────────────────────────────

void Custodian::scanUsbDevices()
{
    if (m_active)
        return;

    const QDir usbDir(QStringLiteral("/sys/bus/usb/devices"));
    const auto entries = usbDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const QString &entry : entries) {
        const QString devPath = usbDir.filePath(entry);

        QFile vidFile(devPath + QStringLiteral("/idVendor"));
        QFile pidFile(devPath + QStringLiteral("/idProduct"));
        if (!vidFile.open(QIODevice::ReadOnly) || !pidFile.open(QIODevice::ReadOnly))
            continue;

        const QString vid = QString::fromLatin1(vidFile.readAll()).trimmed().toLower();
        const QString pid = QString::fromLatin1(pidFile.readAll()).trimmed().toLower();

        for (const CustodianProfile &profile : std::as_const(m_profiles)) {
            if (profile.hidVendorId != vid || profile.hidProductId != pid)
                continue;
            if (profile.hidPayload2D.isEmpty())
                continue;

            qCInfo(KWINVRCUSTODIAN) << "Startup: found" << profile.name
                                    << "USB device" << vid << ":" << pid
                                    << "— sending 2D init";
            sendHidInit(profile, false /* 2D */);
            break;
        }
    }
}

// ─── Startup connector scan ───────────────────────────────────────────────────

void Custodian::scanConnectors()
{
    if (m_active)
        return;

    const QDir sysdrm(QStringLiteral("/sys/class/drm"));
    const auto entries = sysdrm.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const QString &entry : entries) {
        if (!entry.contains(u'-'))
            continue;

        const QString connectorPath = sysdrm.filePath(entry);

        QFile statusFile(connectorPath + QStringLiteral("/status"));
        if (!statusFile.open(QIODevice::ReadOnly))
            continue;
        if (QString::fromLatin1(statusFile.readAll()).trimmed() != QLatin1String("connected"))
            continue;

        const auto profile = matchConnector(connectorPath);
        if (!profile)
            continue;

        const QString modeStr = CustodianProfileLoader::readCurrentMode(connectorPath);
        int w = 0, h = 0;
        if (!CustodianProfileLoader::parseMode(modeStr, w, h))
            continue;

        if (profile->isSbsMode(w, h)) {
            qCInfo(KWINVRCUSTODIAN) << "Startup: found" << profile->name
                                    << "already in SBS mode on"
                                    << outputNameFromConnectorPath(connectorPath);
            activateProfile(*profile, outputNameFromConnectorPath(connectorPath));
            return;
        }
    }
}

// ─── udev event handlers ──────────────────────────────────────────────────────

void Custodian::onDrmConnectorChanged(const QString &connectorPath)
{
    qCDebug(KWINVRCUSTODIAN) << "DRM connector changed:" << connectorPath;

    const auto profile = matchConnector(connectorPath);
    if (!profile)
        return;

    const QString outputName = outputNameFromConnectorPath(connectorPath);

    const QString modeStr = CustodianProfileLoader::readCurrentMode(connectorPath);
    int w = 0, h = 0;
    if (!CustodianProfileLoader::parseMode(modeStr, w, h)) {
        if (m_active && m_activeOutput == outputName) {
            qCInfo(KWINVRCUSTODIAN) << "Connector" << outputName
                                    << "lost mode while VR active — deactivating";
            deactivateActive(QStringLiteral("connector disconnected"));
        }
        return;
    }

    if (profile->isSbsMode(w, h)) {
        if (!m_active) {
            qCInfo(KWINVRCUSTODIAN) << "SBS mode detected on" << outputName
                                    << "for profile" << profile->name;
            activateProfile(*profile, outputName);
        }
    } else if (profile->isDesktopMode(w, h)) {
        if (m_active && m_activeOutput == outputName) {
            qCInfo(KWINVRCUSTODIAN) << "Desktop mode detected on" << outputName
                                    << "— deactivating VR";
            deactivateActive(QStringLiteral("desktop mode detected"));
        }
    }
}

void Custodian::onUsbDeviceAdded(const QString &vendorId,
                                 const QString &productId,
                                 const QString &devNode)
{
    Q_UNUSED(devNode)

    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.hidVendorId.isEmpty() || profile.hidProductId.isEmpty())
            continue;
        if (profile.hidVendorId != vendorId || profile.hidProductId != productId)
            continue;

        qCInfo(KWINVRCUSTODIAN) << "USB device added for profile:" << profile.name
                                << "(" << vendorId << ":" << productId << ")";

        // If VR is already active for this device, the USB reconnected during a
        // HID mode switch. Do not reset to 2D — the device is in SBS mode and
        // resetting it would cause "half on and half off" in the glasses.
        if (m_active && m_activeProfile
            && m_activeProfile->hidVendorId == vendorId
            && m_activeProfile->hidProductId == productId) {
            qCInfo(KWINVRCUSTODIAN) << "USB reconnect during active VR session — not resetting HID mode";
            return;
        }

        if (!profile.hidPayload2D.isEmpty())
            sendHidInit(profile, false /* 2D */);

        return;
    }
}

void Custodian::onUsbDeviceRemoved(const QString &vendorId, const QString &productId)
{
    if (!m_active || !m_activeProfile)
        return;
    if (m_activeProfile->hidVendorId == vendorId && m_activeProfile->hidProductId == productId) {
        qCInfo(KWINVRCUSTODIAN) << "USB device removed for active profile:"
                                << m_activeProfile->name;
        // DRM connector change handles VR deactivation
    }
}

// ─── D-Bus service event handlers ─────────────────────────────────────────────

void Custodian::onRuntimeServiceRegistered(const QString &serviceName)
{
    qCInfo(KWINVRCUSTODIAN) << "OpenXR runtime service appeared:" << serviceName;

    if (m_active && m_activeProfile && m_activeProfile->serviceName == serviceName)
        notifyPluginActivate(m_activeProfile->name, m_activeOutput);

    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.trigger != ProfileTrigger::Service)
            continue;
        if (profile.serviceName == serviceName && !m_active) {
            qCInfo(KWINVRCUSTODIAN) << "Service-triggered profile matched:" << profile.name;
            activateProfile(profile, QString());
            return;
        }
    }
}

void Custodian::onRuntimeServiceUnregistered(const QString &serviceName)
{
    qCInfo(KWINVRCUSTODIAN) << "OpenXR runtime service vanished:" << serviceName;

    if (!m_active || !m_activeProfile)
        return;

    if (m_activeProfile->trigger == ProfileTrigger::Service
        && m_activeProfile->serviceName == serviceName) {
        qCInfo(KWINVRCUSTODIAN) << "Service-triggered VR service gone — deactivating";
        deactivateActive(QStringLiteral("runtime service vanished"));
    }
}

void Custodian::onPluginAppeared()
{
    qCInfo(KWINVRCUSTODIAN) << "kwin-vr plugin appeared on D-Bus";
    m_pluginAvailable = true;

    if (m_active && m_activeProfile)
        notifyPluginActivate(m_activeProfile->name, m_activeOutput);
}

void Custodian::onPluginVanished()
{
    qCInfo(KWINVRCUSTODIAN) << "kwin-vr plugin vanished from D-Bus";
    m_pluginAvailable = false;

    // If we were waiting for the plugin to call vrStopped() before stopping
    // the runtime, we can no longer wait — the plugin is gone.  Execute the
    // deferred stop immediately so the runtime isn't orphaned.
    if (m_pendingRuntimeStop) {
        qCWarning(KWINVRCUSTODIAN) << "Plugin vanished while VR deactivation was pending"
                                   << "— executing deferred runtime stop now";
        executePendingRuntimeStop();
    }
}

// ─── Core activation/deactivation ─────────────────────────────────────────────

static int triggerPriority(ProfileTrigger t)
{
    switch (t) {
    case ProfileTrigger::Edid:
        return 2;
    case ProfileTrigger::Service:
        return 1;
    case ProfileTrigger::Always:
        return 0;
    default:
        return 0;
    }
}

void Custodian::activateProfile(const CustodianProfile &profile, const QString &outputName)
{
    if (m_active) {
        const int newPrio = triggerPriority(profile.trigger);
        const int activePrio = m_activeProfile ? triggerPriority(m_activeProfile->trigger) : 0;
        if (newPrio <= activePrio) {
            qCDebug(KWINVRCUSTODIAN) << "Ignoring activation of" << profile.name
                                     << "— lower or equal priority to active profile"
                                     << (m_activeProfile ? m_activeProfile->name : QString());
            return;
        }
        qCInfo(KWINVRCUSTODIAN) << "Higher-priority profile" << profile.name
                                << "preempting active profile"
                                << (m_activeProfile ? m_activeProfile->name : QString());
        deactivateActive(QStringLiteral("preempted by higher-priority profile"));
    }

    m_activeProfile = profile;
    m_activeOutput = outputName;
    m_active = true;

    qCInfo(KWINVRCUSTODIAN) << "Activating profile:" << profile.name
                            << "on output:" << (outputName.isEmpty() ? QStringLiteral("(none)") : outputName);

    if (!profile.hidPayload3D.isEmpty())
        sendHidInit(profile, true /* 3D */);

    startRuntime(profile);
}

void Custodian::deactivateActive(const QString &reason)
{
    if (!m_active)
        return;

    qCInfo(KWINVRCUSTODIAN) << "Deactivating:" << reason;

    const QString profileName = m_activeProfile ? m_activeProfile->name : QString();
    const CustodianProfile profile = m_activeProfile.value_or(CustodianProfile{});

    // 1. Notify the plugin to begin VR teardown.  The plugin will call vrStopped()
    //    once KWin has torn down the XR session and reconfigured outputs back to
    //    desktop layout.  stopRuntime() is called from vrStopped(), NOT here.
    notifyPluginDeactivate(profileName);

    // 2. Queue HID 2D command to the glasses immediately.  This starts the hardware
    //    mode switch in parallel with the software teardown.
    if (!profile.hidPayload2D.isEmpty())
        sendHidInit(profile, false /* 2D */);

    // 3. Clear active state.
    m_active = false;
    m_activeProfile = std::nullopt;
    m_activeOutput.clear();

    // 4. Stop watching for the Monado socket (no longer relevant).
    if (m_monadoSocketWatcher) {
        m_monadoSocketWatcher->deleteLater();
        m_monadoSocketWatcher = nullptr;
    }

    // 5. Unsubscribe from unit state changes for any in-progress startup watch.
    unsubscribeUnitStateChanges();

    // 6. Arm the deferred runtime stop.
    //    executePendingRuntimeStop() will be triggered by:
    //      a) vrStopped() — plugin confirmed teardown complete  [normal path]
    //      b) onPluginVanished() — plugin crashed before calling vrStopped()  [fallback]
    m_pendingRuntimeStop = true;
    m_stoppingProfile = profile;

    // If the plugin is not on D-Bus right now, nothing will call vrStopped().
    // Execute the stop immediately in this case.
    if (!m_pluginAvailable) {
        qCWarning(KWINVRCUSTODIAN) << "Plugin not on D-Bus — executing runtime stop without vrStopped confirmation";
        executePendingRuntimeStop();
    }
}

// ─── Deferred runtime stop ────────────────────────────────────────────────────

void Custodian::executePendingRuntimeStop()
{
    if (!m_pendingRuntimeStop)
        return;

    m_pendingRuntimeStop = false;
    const CustodianProfile profile = m_stoppingProfile.value_or(CustodianProfile{});
    m_stoppingProfile = std::nullopt;

    qCInfo(KWINVRCUSTODIAN) << "Executing deferred runtime stop for:"
                            << (profile.name.isEmpty() ? QStringLiteral("(unknown)") : profile.name);
    stopRuntime(profile);
}

// ─── Runtime lifecycle ────────────────────────────────────────────────────────

void Custodian::startRuntime(const CustodianProfile &profile)
{
    const QString unit = profile.inferredSystemdUnit();

    if (unit.isEmpty() || profile.openxrRuntime == QLatin1String("none")) {
        notifyPluginActivate(profile.name, m_activeOutput);
        return;
    }

    if (profile.openxrRuntime == QLatin1String("monado")) {
        const QString socketPath = monadoSocketPath();

        if (QFile::exists(socketPath)) {
            // A socket file is present from a previous session.
            // Verify the Monado service is actually running AND the socket
            // is accepting connections before trusting it as "ready".
            if (isServiceActive(unit) && isSocketLive(socketPath)) {
                qCInfo(KWINVRCUSTODIAN) << "Monado already running with live IPC socket — runtime ready";
                notifyPluginActivate(profile.name, m_activeOutput);
                return;
            }

            // Socket is stale (service not active, or socket not accepting connections).
            // Remove it so the filesystem watcher below fires exactly once when the
            // new Monado instance creates a fresh socket.
            qCWarning(KWINVRCUSTODIAN) << "Stale Monado IPC socket detected"
                                       << "(service active:" << isServiceActive(unit)
                                       << ", socket live:" << isSocketLive(socketPath)
                                       << ") — removing before starting fresh instance";
            if (!QFile::remove(socketPath))
                qCWarning(KWINVRCUSTODIAN) << "Failed to remove stale socket:" << socketPath;
        }
    }

    qCInfo(KWINVRCUSTODIAN) << "Starting runtime unit:" << unit;

    // Fire StartUnit and watch the reply to detect systemd-level failures
    // (e.g. unit file not found, dependency not met).
    QDBusMessage startMsg = QDBusMessage::createMethodCall(kSystemdService, kSystemdObject,
                                                           kSystemdManager,
                                                           QStringLiteral("StartUnit"));
    startMsg.setArguments({unit, QStringLiteral("replace")});

    QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(startMsg);
    auto *startWatcher = new QDBusPendingCallWatcher(pending, this);
    connect(startWatcher, &QDBusPendingCallWatcher::finished,
            this, [this, unit](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (reply.isError()) {
            qCWarning(KWINVRCUSTODIAN) << "systemd rejected StartUnit for" << unit
                                       << ":" << reply.error().message();
            // Abort the activation — there is no runtime to wait for.
            m_active = false;
            m_activeProfile = std::nullopt;
            m_activeOutput.clear();
            m_pendingRuntimeStop = false;
            m_stoppingProfile = std::nullopt;
            if (m_monadoSocketWatcher) {
                m_monadoSocketWatcher->deleteLater();
                m_monadoSocketWatcher = nullptr;
            }
            unsubscribeUnitStateChanges();
            return;
        }
        qCInfo(KWINVRCUSTODIAN) << "StartUnit accepted, job:" << reply.value().path();
    });

    if (profile.openxrRuntime == QLatin1String("monado")) {
        const QString socketPath = monadoSocketPath();
        const QString runtimeDir = socketPath.left(socketPath.lastIndexOf(u'/'));

        // Watch the runtime directory for the Monado IPC socket to appear.
        // Monado creates this socket after Vulkan init is complete and it is
        // ready to accept OpenXR connections.
        m_monadoSocketWatcher = new QFileSystemWatcher({runtimeDir}, this);
        connect(m_monadoSocketWatcher, &QFileSystemWatcher::directoryChanged,
                this, &Custodian::onMonadoSocketAppeared);

        // Also subscribe to the unit's PropertiesChanged signal so we know if
        // Monado enters "failed" state after starting (e.g. crashes during Vulkan init).
        // Use LoadUnit (synchronous) to get the unit object path immediately.
        QDBusMessage loadMsg = QDBusMessage::createMethodCall(kSystemdService, kSystemdObject,
                                                              kSystemdManager,
                                                              QStringLiteral("LoadUnit"));
        loadMsg.setArguments({unit});
        const QDBusMessage loadReply = QDBusConnection::sessionBus().call(loadMsg, QDBus::Block, 3000);
        if (loadReply.type() == QDBusMessage::ReplyMessage && !loadReply.arguments().isEmpty()) {
            const QString unitPath = loadReply.arguments().first().value<QDBusObjectPath>().path();
            if (!unitPath.isEmpty())
                subscribeUnitStateChanges(unitPath);
        } else {
            qCWarning(KWINVRCUSTODIAN) << "Could not get unit object path for" << unit
                                       << "— startup failure detection disabled";
        }

        qCInfo(KWINVRCUSTODIAN) << "Watching for Monado IPC socket:" << socketPath;

    } else if (profile.openxrRuntime == QLatin1String("wivrn")) {
        qCInfo(KWINVRCUSTODIAN) << "Waiting for WiVRn D-Bus service:"
                                << (profile.serviceName.isEmpty()
                                        ? QStringLiteral("net.wivrn.Server")
                                        : profile.serviceName);
    }
}

void Custodian::onMonadoSocketAppeared()
{
    if (!m_activeProfile || m_activeProfile->openxrRuntime != QLatin1String("monado"))
        return;

    const QString socketPath = monadoSocketPath();

    if (!QFile::exists(socketPath))
        return; // Directory change was for something else — keep watching

    // Verify the socket is genuinely accepting connections, not just a file.
    // On NVIDIA, Monado's Vulkan init takes a moment after creating the socket
    // file; the connect check confirms the IPC server is actually listening.
    if (!isSocketLive(socketPath)) {
        qCDebug(KWINVRCUSTODIAN) << "Monado IPC socket file appeared but is not yet"
                                    " accepting connections — continuing to watch";
        return; // Watcher will fire again on next directory change
    }

    qCInfo(KWINVRCUSTODIAN) << "Monado IPC socket appeared and verified live — runtime ready";

    // Stop watching: socket is confirmed live; no longer need the watcher.
    if (m_monadoSocketWatcher) {
        m_monadoSocketWatcher->deleteLater();
        m_monadoSocketWatcher = nullptr;
    }

    // Unsubscribe from startup failure detection — Monado is running successfully.
    unsubscribeUnitStateChanges();

    notifyPluginActivate(m_activeProfile->name, m_activeOutput);
}

void Custodian::subscribeUnitStateChanges(const QString &unitPath)
{
    // Unsubscribe from any previous watcher first.
    unsubscribeUnitStateChanges();
    m_startingUnitPath = unitPath;

    // Connect to org.freedesktop.DBus.Properties.PropertiesChanged on the unit object.
    // This fires when ActiveState changes (e.g. "activating" → "active" or "failed").
    const bool ok = QDBusConnection::sessionBus().connect(
        kSystemdService,
        m_startingUnitPath,
        kDBusProperties,
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onStartingUnitPropertiesChanged(QString, QVariantMap, QStringList)));

    if (!ok)
        qCWarning(KWINVRCUSTODIAN) << "Failed to subscribe to unit PropertiesChanged for"
                                   << unitPath;
    else
        qCDebug(KWINVRCUSTODIAN) << "Subscribed to unit state changes for" << unitPath;
}

void Custodian::unsubscribeUnitStateChanges()
{
    if (m_startingUnitPath.isEmpty())
        return;

    QDBusConnection::sessionBus().disconnect(
        kSystemdService,
        m_startingUnitPath,
        kDBusProperties,
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onStartingUnitPropertiesChanged(QString, QVariantMap, QStringList)));

    m_startingUnitPath.clear();
}

void Custodian::onStartingUnitPropertiesChanged(const QString &iface,
                                                const QVariantMap &changed,
                                                const QStringList &invalidated)
{
    Q_UNUSED(iface)
    Q_UNUSED(invalidated)

    const QString state = changed.value(QLatin1String("ActiveState")).toString();
    if (state.isEmpty())
        return;

    qCDebug(KWINVRCUSTODIAN) << "Runtime unit state changed to:" << state;

    if (state == QLatin1String("failed")) {
        qCWarning(KWINVRCUSTODIAN) << "Runtime unit entered 'failed' state during startup"
                                   << "— aborting VR activation";
        unsubscribeUnitStateChanges();

        if (m_monadoSocketWatcher) {
            m_monadoSocketWatcher->deleteLater();
            m_monadoSocketWatcher = nullptr;
        }

        // Clear activation state — nothing to stop (unit already failed).
        m_active = false;
        m_activeProfile = std::nullopt;
        m_activeOutput.clear();
        m_pendingRuntimeStop = false;
        m_stoppingProfile = std::nullopt;
    }
}

void Custodian::stopRuntime(const CustodianProfile &profile)
{
    const QString unit = profile.inferredSystemdUnit();
    if (unit.isEmpty() || profile.openxrRuntime == QLatin1String("none"))
        return;

    qCInfo(KWINVRCUSTODIAN) << "Stopping runtime unit:" << unit;

    QDBusMessage msg = QDBusMessage::createMethodCall(kSystemdService, kSystemdObject,
                                                      kSystemdManager,
                                                      QStringLiteral("StopUnit"));
    msg.setArguments({unit, QStringLiteral("replace")});

    QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(msg);
    auto *stopWatcher = new QDBusPendingCallWatcher(pending, this);
    connect(stopWatcher, &QDBusPendingCallWatcher::finished,
            this, [unit](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (reply.isError())
            qCWarning(KWINVRCUSTODIAN) << "StopUnit reply error for" << unit
                                       << ":" << reply.error().message();
        else
            qCInfo(KWINVRCUSTODIAN) << "StopUnit accepted for" << unit
                                    << ", job:" << reply.value().path();
    });
}

// ─── HID init ─────────────────────────────────────────────────────────────────

void Custodian::sendHidInit(const CustodianProfile &profile, bool sbsMode)
{
    if (profile.hidVendorId.isEmpty() || profile.hidProductId.isEmpty())
        return;

    const QByteArray &payload = sbsMode ? profile.hidPayload3D : profile.hidPayload2D;
    if (payload.isEmpty())
        return;

    qCInfo(KWINVRCUSTODIAN) << "Sending HID init to"
                            << profile.hidVendorId << ":" << profile.hidProductId
                            << "(mode:" << (sbsMode ? "3D" : "2D") << ")";

    m_hidInit->sendCommand(profile.hidVendorId, profile.hidProductId,
                           profile.hidInterface, payload);
}

// ─── Plugin notification ──────────────────────────────────────────────────────

void Custodian::notifyPluginActivate(const QString &profileName, const QString &outputName)
{
    qCInfo(KWINVRCUSTODIAN) << "Notifying plugin: activate profile" << profileName
                            << "on output" << (outputName.isEmpty() ? QStringLiteral("(none)") : outputName);

    Q_EMIT profileActivated(profileName, outputName);

    if (!m_pluginAvailable) {
        qCWarning(KWINVRCUSTODIAN) << "kwin-vr plugin not on D-Bus — signal may be missed";
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(kPluginService, kPluginObject,
                                                      kPluginInterface,
                                                      QStringLiteral("requestActivateProfile"));
    msg.setArguments({profileName, outputName});
    QDBusConnection::sessionBus().asyncCall(msg);
}

void Custodian::notifyPluginDeactivate(const QString &profileName)
{
    qCInfo(KWINVRCUSTODIAN) << "Notifying plugin: deactivate profile" << profileName;

    Q_EMIT profileDeactivated(profileName);

    if (!m_pluginAvailable)
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(kPluginService, kPluginObject,
                                                      kPluginInterface,
                                                      QStringLiteral("requestDeactivate"));
    QDBusConnection::sessionBus().asyncCall(msg);
}

// ─── D-Bus setup ──────────────────────────────────────────────────────────────

void Custodian::registerDBusService()
{
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(kCustodianService)) {
        qCWarning(KWINVRCUSTODIAN) << "Failed to register D-Bus service:" << kCustodianService;
        return;
    }
    if (!bus.registerObject(kCustodianObject, this,
                            QDBusConnection::ExportScriptableSlots
                                | QDBusConnection::ExportScriptableSignals)) {
        qCWarning(KWINVRCUSTODIAN) << "Failed to register D-Bus object:" << kCustodianObject;
    } else {
        qCInfo(KWINVRCUSTODIAN) << "D-Bus service registered:" << kCustodianService;
    }
}

void Custodian::setupRuntimeWatcher()
{
    QStringList serviceNames;
    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.trigger == ProfileTrigger::Service && !profile.serviceName.isEmpty())
            serviceNames.append(profile.serviceName);
        if (profile.openxrRuntime == QLatin1String("wivrn") && !profile.serviceName.isEmpty())
            serviceNames.append(profile.serviceName);
    }

    if (serviceNames.isEmpty())
        return;

    if (!m_runtimeWatcher) {
        m_runtimeWatcher = new QDBusServiceWatcher(this);
        m_runtimeWatcher->setConnection(QDBusConnection::sessionBus());
        m_runtimeWatcher->setWatchMode(QDBusServiceWatcher::WatchForRegistration
                                       | QDBusServiceWatcher::WatchForUnregistration);
        connect(m_runtimeWatcher, &QDBusServiceWatcher::serviceRegistered,
                this, &Custodian::onRuntimeServiceRegistered);
        connect(m_runtimeWatcher, &QDBusServiceWatcher::serviceUnregistered,
                this, &Custodian::onRuntimeServiceUnregistered);
    }

    serviceNames.removeDuplicates();
    for (const QString &svc : std::as_const(serviceNames))
        m_runtimeWatcher->addWatchedService(svc);

    auto iface = QDBusConnection::sessionBus().interface();
    for (const QString &svc : std::as_const(serviceNames)) {
        if (iface && iface->isServiceRegistered(svc).value())
            onRuntimeServiceRegistered(svc);
    }
}

void Custodian::setupPluginWatcher()
{
    m_pluginWatcher = new QDBusServiceWatcher(kPluginService,
                                              QDBusConnection::sessionBus(),
                                              QDBusServiceWatcher::WatchForRegistration
                                                  | QDBusServiceWatcher::WatchForUnregistration,
                                              this);
    connect(m_pluginWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, [this](const QString &) {
        onPluginAppeared();
    });
    connect(m_pluginWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, [this](const QString &) {
        onPluginVanished();
    });

    auto iface = QDBusConnection::sessionBus().interface();
    if (iface && iface->isServiceRegistered(kPluginService).value())
        onPluginAppeared();
}

// ─── D-Bus slots from the plugin ──────────────────────────────────────────────

void Custodian::vrReady()
{
    qCInfo(KWINVRCUSTODIAN) << "Plugin reported VR ready";
}

void Custodian::vrStopped()
{
    qCInfo(KWINVRCUSTODIAN) << "Plugin confirmed VR fully stopped"
                            << "— executing deferred runtime stop";
    executePendingRuntimeStop();
}

void Custodian::manualActivate()
{
    qCInfo(KWINVRCUSTODIAN) << "Manual VR activation requested";

    if (m_active) {
        qCInfo(KWINVRCUSTODIAN) << "VR already active — ignoring manual activate";
        return;
    }

    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.trigger == ProfileTrigger::Always) {
            activateProfile(profile, QString());
            return;
        }
    }

    notifyPluginActivate(QString(), QString());
}

// ─── DRM sysfs helpers ────────────────────────────────────────────────────────

std::optional<CustodianProfile> Custodian::matchConnector(const QString &connectorPath) const
{
    const QByteArray edid = CustodianProfileLoader::readEdid(connectorPath);
    if (edid.isEmpty())
        return std::nullopt;

    QString vendor;
    quint16 productId = 0;
    const bool hasVendorProduct = CustodianProfileLoader::parseEdidVendorProduct(edid, vendor, productId);
    const QString monitorName = CustodianProfileLoader::parseEdidMonitorName(edid);

    for (const CustodianProfile &profile : m_profiles) {
        if (profile.trigger != ProfileTrigger::Edid)
            continue;

        bool edidMatch = false;
        if (hasVendorProduct && !profile.edidVendor.isEmpty()) {
            edidMatch = profile.matchesEdidVendor(vendor)
                && (profile.edidProductId == 0 || profile.edidProductId == productId);
        }
        if (!edidMatch && !profile.edidName.isEmpty())
            edidMatch = profile.matchesEdidName(monitorName);

        if (edidMatch) {
            qCDebug(KWINVRCUSTODIAN) << "Connector" << connectorPath
                                     << "matched profile" << profile.name
                                     << "(vendor:" << vendor << "name:" << monitorName << ")";
            return profile;
        }
    }

    return std::nullopt;
}

QString Custodian::outputNameFromConnectorPath(const QString &connectorPath)
{
    const QString base = QDir(connectorPath).dirName();
    const int dash = base.indexOf(u'-');
    if (dash < 0)
        return base;
    return base.mid(dash + 1);
}

// ─── System state verification helpers ───────────────────────────────────────

bool Custodian::isServiceActive(const QString &unit) const
{
    // GetUnit returns the object path for the unit, or an error if not loaded.
    QDBusMessage getUnit = QDBusMessage::createMethodCall(kSystemdService, kSystemdObject,
                                                          kSystemdManager,
                                                          QStringLiteral("GetUnit"));
    getUnit.setArguments({unit});
    const QDBusMessage reply = QDBusConnection::sessionBus().call(getUnit, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        qCDebug(KWINVRCUSTODIAN) << "GetUnit failed for" << unit
                                 << "(likely not loaded) — treating as inactive";
        return false;
    }

    const QString unitPath = reply.arguments().first().value<QDBusObjectPath>().path();
    if (unitPath.isEmpty())
        return false;

    QDBusInterface unitIface(kSystemdService, unitPath, kSystemdUnit,
                             QDBusConnection::sessionBus());
    const QString state = unitIface.property("ActiveState").toString();
    qCDebug(KWINVRCUSTODIAN) << "Unit" << unit << "ActiveState:" << state;

    return state == QLatin1String("active") || state == QLatin1String("activating");
}

// static
bool Custodian::isSocketLive(const QString &socketPath)
{
    // Attempt a non-blocking connect to the Unix domain socket.
    // Returns true if a server is listening (EINPROGRESS = connect in progress,
    // which means listen() has been called).  Returns false on ECONNREFUSED
    // (file exists but no server) or other hard errors.
    const int sock = ::socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (sock < 0)
        return false;

    struct sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    const QByteArray pathBytes = socketPath.toLocal8Bit();
    if (pathBytes.size() >= static_cast<int>(sizeof(addr.sun_path))) {
        ::close(sock);
        return false;
    }
    std::memcpy(addr.sun_path, pathBytes.constData(), pathBytes.size());

    const int ret = ::connect(sock, reinterpret_cast<struct sockaddr *>(&addr),
                              static_cast<socklen_t>(sizeof(addr)));
    const int err = errno;
    ::close(sock);

    // ret == 0: connected immediately (shouldn't happen for IPC but handle it)
    // EINPROGRESS: non-blocking connect queued — server is listening
    // EAGAIN: resource temporarily unavailable — server is listening
    // ECONNREFUSED: no server listening on this socket
    return ret == 0 || err == EINPROGRESS || err == EAGAIN;
}

QString Custodian::monadoSocketPath() const
{
    const QString runtimeDir = qEnvironmentVariable(
        "XDG_RUNTIME_DIR",
        QStringLiteral("/run/user/") + QString::number(::getuid()));
    return runtimeDir + QStringLiteral("/monado_comp_ipc");
}
