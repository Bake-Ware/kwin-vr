/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "custodianprofile.h"

#include <QDBusObjectPath>
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
 *   3. When runtime is ready (socket live + service active), the plugin is notified
 *   4. On deactivation, runtime is stopped only AFTER the plugin confirms teardown
 *
 * All state transitions are event-driven — no polling, no arbitrary sleeps.
 * Device-specific logic lives entirely in profile files; this class is generic.
 *
 * Deactivation ordering invariant (prevents NVIDIA GPU deadlock):
 *   plugin confirmed VR stopped → KWin outputs reconfigured → THEN stopRuntime()
 *   This ensures Monado's Vulkan compositor is never torn down while the display
 *   pipeline is still in SBS/VR mode.
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
     * Called by the kwin-vr plugin once VR teardown is complete and KWin has
     * reconfigured its outputs back to desktop layout.
     *
     * This is the trigger for stopping the OpenXR runtime. Stopping Monado BEFORE
     * this callback fires risks tearing down its Vulkan compositor while the display
     * is still in SBS mode, which causes a GPU deadlock on NVIDIA hardware.
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
     * The kwin-vr plugin should call setVrActive(false) in response, then call
     * vrStopped() once teardown is complete.
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

    /**
     * Execute the deferred runtime stop.
     * Called from vrStopped() (normal path) or onPluginVanished() (fallback).
     * Guards against double-execution via m_pendingRuntimeStop.
     */
    void executePendingRuntimeStop();

    // Monado startup monitoring
    void onMonadoSocketAppeared();
    void subscribeUnitStateChanges(const QString &unitPath);
    void unsubscribeUnitStateChanges();

    // Slot connected to org.freedesktop.DBus.Properties.PropertiesChanged on the unit object.
    // Detects Monado entering "failed" state during startup.
    Q_SLOT void onStartingUnitPropertiesChanged(const QString &iface,
                                                const QVariantMap &changed,
                                                const QStringList &invalidated);

    // HID init
    void sendHidInit(const CustodianProfile &profile, bool sbsMode);

    // Notify the kwin-vr plugin (async D-Bus call — does not block)
    void notifyPluginActivate(const QString &profileName, const QString &outputName);
    void notifyPluginDeactivate(const QString &profileName);

    // D-Bus helpers
    void registerDBusService();
    void setupRuntimeWatcher();
    void setupPluginWatcher();

    /**
     * Query systemd D-Bus to check if a unit is active or activating.
     * Synchronous (blocking) — only call when a fast answer is needed and
     * the caller is already handling an edge case (e.g. stale socket detected).
     */
    bool isServiceActive(const QString &unit) const;

    /**
     * Attempt a non-blocking connect to a Unix domain socket.
     * Returns true if something is listening (EINPROGRESS/EAGAIN/success).
     * Returns false if ECONNREFUSED — socket file exists but no server.
     */
    static bool isSocketLive(const QString &socketPath);

    /** Full path to the Monado IPC socket in XDG_RUNTIME_DIR. */
    QString monadoSocketPath() const;

    // DRM sysfs helpers
    std::optional<CustodianProfile> matchConnector(const QString &connectorPath) const;
    static QString outputNameFromConnectorPath(const QString &connectorPath);

    // ── Profile state ────────────────────────────────────────────────────────
    QList<CustodianProfile> m_profiles;
    QFileSystemWatcher *m_profileWatcher = nullptr;

    // ── Hardware monitors ────────────────────────────────────────────────────
    UdevMonitor *m_udev = nullptr;
    HidInit *m_hidInit = nullptr;

    // ── D-Bus service watchers ───────────────────────────────────────────────
    QDBusServiceWatcher *m_runtimeWatcher = nullptr; // OpenXR runtime services (WiVRn etc.)
    QDBusServiceWatcher *m_pluginWatcher = nullptr; // kwin-vr plugin

    // ── Monado startup monitoring ────────────────────────────────────────────
    // Watches XDG_RUNTIME_DIR for the Monado IPC socket to appear
    QFileSystemWatcher *m_monadoSocketWatcher = nullptr;
    // Systemd unit object path for the currently-starting runtime (used for PropertiesChanged)
    QString m_startingUnitPath;

    // ── Active session state ─────────────────────────────────────────────────
    std::optional<CustodianProfile> m_activeProfile;
    QString m_activeOutput;
    bool m_active = false;
    bool m_pluginAvailable = false;

    // ── Deferred runtime stop state ──────────────────────────────────────────
    // Set to true in deactivateActive(). Cleared and acted on in vrStopped()
    // (normal path) or onPluginVanished() (fallback). This defers stopRuntime()
    // until KWin has confirmed VR teardown, preventing the NVIDIA GPU deadlock
    // that occurs when Monado is stopped while the display is still in SBS mode.
    bool m_pendingRuntimeStop = false;
    std::optional<CustodianProfile> m_stoppingProfile;
};
