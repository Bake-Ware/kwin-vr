/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "custodianprofile.h"

#include <QDBusServiceWatcher>
#include <QFileSystemWatcher>
#include <QObject>
#include <QString>

#include <optional>

class HidInit;
class UdevMonitor;

/**
 * Custodian — the hardware observer and event router for kwin-vr.
 *
 * Watches four event sources simultaneously:
 *   udev   — DRM connector EDID/mode changes, USB device hotplug
 *   D-Bus  — OpenXR runtime service state, KWin plugin availability
 *   inotify — Profile directory changes (hot-reload without restart)
 *   systemd — Runtime unit state via org.freedesktop.systemd1
 *
 * When a profile matches:
 *   1. HID init payload is sent (device-specific display mode switch)
 *   2. OpenXR runtime is started via systemd D-Bus
 *   3. When runtime is ready, the kwin-vr plugin is notified via D-Bus
 *
 * All state transitions are event-driven — no polling, no arbitrary sleeps.
 * Device-specific logic lives entirely in profile files; this class is generic.
 */
class Custodian : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwinvr.Custodian")

public:
    explicit Custodian(QObject *parent = nullptr);
    ~Custodian() override;

    /**
     * Initialise all monitors and register the D-Bus service.
     * Returns false if a fatal initialisation error occurs.
     */
    bool start();

public Q_SLOTS:
    /**
     * Called by the kwin-vr plugin once its VR layout is fully set up.
     * This is informational — the custodian uses it for logging/state tracking.
     */
    Q_SCRIPTABLE void vrReady();

    /**
     * Called by the kwin-vr plugin once VR teardown is complete.
     * The custodian stops the OpenXR runtime after receiving this.
     */
    Q_SCRIPTABLE void vrStopped();

    /**
     * Called by the kwin-vr plugin when the user manually requests VR from
     * the settings UI and no display profile has matched automatically.
     * The custodian activates the flat_monitor (Always-trigger) fallback.
     */
    Q_SCRIPTABLE void manualActivate();

Q_SIGNALS:
    /**
     * Emitted when a profile has matched hardware and the OpenXR runtime is
     * ready to accept connections. The kwin-vr plugin should call
     * requestActivateProfile() in response.
     *
     * outputName is the KWin output identifier, e.g. "DP-1".
     */
    Q_SCRIPTABLE void profileActivated(const QString &profileName, const QString &outputName);

    /**
     * Emitted when the matched hardware has gone away or the user stopped VR.
     * The kwin-vr plugin should call setVrActive(false) in response.
     */
    Q_SCRIPTABLE void profileDeactivated(const QString &profileName);

private:
    // Profile management
    void reloadProfiles();
    void setupProfileWatcher(const QString &directory);

    // Startup scans — check hardware already present when the custodian launches
    void scanConnectors();
    void scanUsbDevices();

    // udev event handlers
    void onDrmConnectorChanged(const QString &connectorPath);
    void onUsbDeviceAdded(const QString &vendorId, const QString &productId, const QString &devNode);
    void onUsbDeviceRemoved(const QString &vendorId, const QString &productId);

    // D-Bus service event handlers
    void onRuntimeServiceRegistered(const QString &serviceName);
    void onRuntimeServiceUnregistered(const QString &serviceName);
    void onPluginAppeared();
    void onPluginVanished();

    // Core activation/deactivation
    void activateProfile(const CustodianProfile &profile, const QString &outputName);
    void deactivateActive(const QString &reason);

    // Runtime lifecycle
    void startRuntime(const CustodianProfile &profile);
    void stopRuntime(const CustodianProfile &profile);
    void onMonadoSocketAppeared();

    // HID init
    void sendHidInit(const CustodianProfile &profile, bool sbsMode);

    // Notify the kwin-vr plugin (async D-Bus call — does not block)
    void notifyPluginActivate(const QString &profileName, const QString &outputName);
    void notifyPluginDeactivate(const QString &profileName);

    // D-Bus helpers
    void registerDBusService();
    void setupRuntimeWatcher();
    void setupPluginWatcher();

    // DRM sysfs helpers

    /**
     * Check whether a connector's EDID matches any loaded profile.
     * Returns the matching profile, or std::nullopt.
     */
    std::optional<CustodianProfile> matchConnector(const QString &connectorPath) const;

    /**
     * Extract the KWin output name from a DRM connector sysfs path.
     * e.g. /sys/class/drm/card1-DP-1  →  "DP-1"
     */
    static QString outputNameFromConnectorPath(const QString &connectorPath);

    QList<CustodianProfile> m_profiles;
    QFileSystemWatcher *m_profileWatcher = nullptr;

    UdevMonitor *m_udev = nullptr;
    HidInit *m_hidInit = nullptr;

    // Watches for OpenXR runtime services (WiVRn etc.) on the session bus
    QDBusServiceWatcher *m_runtimeWatcher = nullptr;
    // Watches for the kwin-vr plugin service
    QDBusServiceWatcher *m_pluginWatcher = nullptr;

    // Watches for the Monado IPC socket appearing in XDG_RUNTIME_DIR
    QFileSystemWatcher *m_monadoSocketWatcher = nullptr;

    std::optional<CustodianProfile> m_activeProfile;
    QString m_activeOutput;
    bool m_pluginAvailable = false;
    bool m_active = false;
};
