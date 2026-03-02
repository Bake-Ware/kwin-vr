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
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>

#include <unistd.h> // getuid()

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

    // Rebuild the D-Bus runtime watcher for any service-triggered profiles
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
    // Walk /sys/bus/usb/devices to find any VR device already connected.
    // For each match, send the 2D HID init payload so the device starts in
    // desktop mode (mirrors what the old boot-init script did).
    // Skip entirely if VR is already active — scanConnectors() already handled
    // the SBS activation and we must not reset the device to 2D mode.
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
            break; // One init per physical device
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
        // Only connector entries (contain a dash after the card name)
        if (!entry.contains(u'-'))
            continue;

        const QString connectorPath = sysdrm.filePath(entry);

        // Must be connected
        QFile statusFile(connectorPath + QStringLiteral("/status"));
        if (!statusFile.open(QIODevice::ReadOnly))
            continue;
        if (QString::fromLatin1(statusFile.readAll()).trimmed() != QLatin1String("connected"))
            continue;

        const auto profile = matchConnector(connectorPath);
        if (!profile)
            continue;

        // Check if already in SBS mode
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
        // No current mode — connector may have disconnected
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

    // Find a profile matching this USB device for HID init
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

        // Send 2D init payload — device just connected, put it in desktop mode
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
        // The DRM connector change will handle VR deactivation; no action needed here
    }
}

// ─── D-Bus service event handlers ─────────────────────────────────────────────

void Custodian::onRuntimeServiceRegistered(const QString &serviceName)
{
    qCInfo(KWINVRCUSTODIAN) << "OpenXR runtime service appeared:" << serviceName;

    // For WiVRn: runtime appearing on D-Bus means it's ready
    if (m_active && m_activeProfile && m_activeProfile->serviceName == serviceName) {
        notifyPluginActivate(m_activeProfile->name, m_activeOutput);
    }

    // For service-triggered profiles: runtime appearing is the trigger
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

    // If we were already active (e.g. custodian restarted), re-notify
    if (m_active && m_activeProfile)
        notifyPluginActivate(m_activeProfile->name, m_activeOutput);
}

void Custodian::onPluginVanished()
{
    qCInfo(KWINVRCUSTODIAN) << "kwin-vr plugin vanished from D-Bus";
    m_pluginAvailable = false;
}

// ─── Core activation/deactivation ─────────────────────────────────────────────

void Custodian::activateProfile(const CustodianProfile &profile, const QString &outputName)
{
    if (m_active) {
        qCDebug(KWINVRCUSTODIAN) << "Ignoring activation — VR already active";
        return;
    }

    m_activeProfile = profile;
    m_activeOutput = outputName;
    m_active = true;

    qCInfo(KWINVRCUSTODIAN) << "Activating profile:" << profile.name
                            << "on output:" << (outputName.isEmpty() ? QStringLiteral("(none)") : outputName);

    // 1. Send HID init for 3D/SBS mode
    if (!profile.hidPayload3D.isEmpty())
        sendHidInit(profile, true /* 3D */);

    // 2. Start the OpenXR runtime and wait for it to be ready
    startRuntime(profile);
}

void Custodian::deactivateActive(const QString &reason)
{
    if (!m_active)
        return;

    qCInfo(KWINVRCUSTODIAN) << "Deactivating:" << reason;

    const QString profileName = m_activeProfile ? m_activeProfile->name : QString();
    const CustodianProfile profile = m_activeProfile.value_or(CustodianProfile{});

    // 1. Notify the plugin — it will call vrStopped() when done
    notifyPluginDeactivate(profileName);

    // 2. Send HID init for 2D/desktop mode
    if (!profile.hidPayload2D.isEmpty())
        sendHidInit(profile, false /* 2D */);

    // 3. Stop the runtime
    // We stop immediately — the plugin handles XR_ERROR_SESSION_LOST gracefully.
    // vrStopped() from the plugin is still accepted for any post-teardown actions.
    stopRuntime(profile);

    m_active = false;
    m_activeProfile = std::nullopt;
    m_activeOutput.clear();

    // Clean up any pending Monado socket watcher
    if (m_monadoSocketWatcher) {
        m_monadoSocketWatcher->deleteLater();
        m_monadoSocketWatcher = nullptr;
    }
}

// ─── Runtime lifecycle ────────────────────────────────────────────────────────

void Custodian::startRuntime(const CustodianProfile &profile)
{
    const QString unit = profile.inferredSystemdUnit();

    if (unit.isEmpty() || profile.openxrRuntime == QLatin1String("none")) {
        // No runtime to start — notify plugin immediately
        notifyPluginActivate(profile.name, m_activeOutput);
        return;
    }

    qCInfo(KWINVRCUSTODIAN) << "Starting runtime unit:" << unit;

    // Start the systemd user unit (non-blocking async call)
    QDBusMessage msg = QDBusMessage::createMethodCall(kSystemdService,
                                                      kSystemdObject,
                                                      kSystemdManager,
                                                      QStringLiteral("StartUnit"));
    msg.setArguments({unit, QStringLiteral("replace")});
    QDBusConnection::sessionBus().asyncCall(msg);

    if (profile.openxrRuntime == QLatin1String("monado")) {
        // Wait for the Monado IPC socket to appear — that's when Monado is ready
        const QString runtimeDir = qEnvironmentVariable(
            "XDG_RUNTIME_DIR",
            QStringLiteral("/run/user/") + QString::number(::getuid()));
        const QString socketPath = runtimeDir + QStringLiteral("/monado_comp_ipc");

        // If Monado is already running and the socket is live, notify immediately
        // rather than deleting the socket from under the active OpenXR session.
        if (QFile::exists(socketPath)) {
            qCInfo(KWINVRCUSTODIAN) << "Monado IPC socket already present — runtime is ready";
            notifyPluginActivate(profile.name, m_activeOutput);
            return;
        }

        // Remove any stale socket left by a crashed Monado so the watcher
        // fires only when the new instance creates a fresh socket.
        QFile::remove(socketPath);

        // Watch the runtime directory for the socket to appear
        m_monadoSocketWatcher = new QFileSystemWatcher({runtimeDir}, this);
        connect(m_monadoSocketWatcher, &QFileSystemWatcher::directoryChanged,
                this, &Custodian::onMonadoSocketAppeared);

        qCInfo(KWINVRCUSTODIAN) << "Watching for Monado IPC socket:" << socketPath;
    } else if (profile.openxrRuntime == QLatin1String("wivrn")) {
        // WiVRn registers on D-Bus when ready — onRuntimeServiceRegistered() handles it.
        // The runtimeWatcher was already set up for this service name in setupRuntimeWatcher().
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

    const QString runtimeDir = qEnvironmentVariable(
        "XDG_RUNTIME_DIR",
        QStringLiteral("/run/user/") + QString::number(::getuid()));
    const QString socketPath = runtimeDir + QStringLiteral("/monado_comp_ipc");

    if (!QFile::exists(socketPath))
        return;

    qCInfo(KWINVRCUSTODIAN) << "Monado IPC socket appeared — runtime is ready";

    // Socket appeared — clean up the watcher
    if (m_monadoSocketWatcher) {
        m_monadoSocketWatcher->deleteLater();
        m_monadoSocketWatcher = nullptr;
    }

    notifyPluginActivate(m_activeProfile->name, m_activeOutput);
}

void Custodian::stopRuntime(const CustodianProfile &profile)
{
    const QString unit = profile.inferredSystemdUnit();
    if (unit.isEmpty() || profile.openxrRuntime == QLatin1String("none"))
        return;

    qCInfo(KWINVRCUSTODIAN) << "Stopping runtime unit:" << unit;

    QDBusMessage msg = QDBusMessage::createMethodCall(kSystemdService,
                                                      kSystemdObject,
                                                      kSystemdManager,
                                                      QStringLiteral("StopUnit"));
    msg.setArguments({unit, QStringLiteral("replace")});
    QDBusConnection::sessionBus().asyncCall(msg);
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

    // Also call the plugin's requestActivateProfile method directly
    QDBusMessage msg = QDBusMessage::createMethodCall(kPluginService,
                                                      kPluginObject,
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

    QDBusMessage msg = QDBusMessage::createMethodCall(kPluginService,
                                                      kPluginObject,
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
    // Collect all D-Bus service names from service-triggered profiles
    QStringList serviceNames;
    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.trigger == ProfileTrigger::Service && !profile.serviceName.isEmpty())
            serviceNames.append(profile.serviceName);
        // WiVRn runtime also registers a D-Bus service when ready
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

    // Remove duplicates before adding
    serviceNames.removeDuplicates();
    for (const QString &svc : std::as_const(serviceNames))
        m_runtimeWatcher->addWatchedService(svc);

    // Check whether any service is already registered
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

    // Check whether the plugin is already running
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
    qCInfo(KWINVRCUSTODIAN) << "Plugin reported VR stopped";
    // Runtime was already stopped in deactivateActive(); nothing more to do.
}

void Custodian::manualActivate()
{
    qCInfo(KWINVRCUSTODIAN) << "Manual VR activation requested";

    if (m_active) {
        qCInfo(KWINVRCUSTODIAN) << "VR already active — ignoring manual activate";
        return;
    }

    // Find an Always-trigger (flat_monitor) fallback profile
    for (const CustodianProfile &profile : std::as_const(m_profiles)) {
        if (profile.trigger == ProfileTrigger::Always) {
            activateProfile(profile, QString());
            return;
        }
    }

    // No fallback profile — notify plugin anyway; it will activate on the current primary output
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

        // Match by binary vendor code (preferred) or monitor name substring
        bool edidMatch = false;
        if (hasVendorProduct && !profile.edidVendor.isEmpty()) {
            edidMatch = profile.matchesEdidVendor(vendor)
                && (profile.edidProductId == 0 || profile.edidProductId == productId);
        }
        if (!edidMatch && !profile.edidName.isEmpty()) {
            edidMatch = profile.matchesEdidName(monitorName);
        }

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
    // e.g. /sys/class/drm/card1-DP-1  →  "DP-1"
    const QString base = QDir(connectorPath).dirName(); // "card1-DP-1"
    const int dash = base.indexOf(u'-');
    if (dash < 0)
        return base;
    return base.mid(dash + 1);
}
