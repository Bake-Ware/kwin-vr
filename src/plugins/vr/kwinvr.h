/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVR_H
#define KWINVR_H

#pragma once

#include <KConfigWatcher>
#include <KNotification>

#include <QDBusServiceWatcher>
#include <QKeySequence>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QSet>
#include <QTimer>

#include <plugin.h>

#include "kwinvrbridge.h"
#include "openxrtest.h"
#include "vrprofile.h"

namespace KWin
{

class Output;

class KwinVr : public Plugin
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwinvr")
    Q_PROPERTY(bool vrActive READ vrActive WRITE setVrActive NOTIFY vrActiveChanged)
public:
    explicit KwinVr();
    ~KwinVr();

    bool vrActive() const;
    void setVrActive(bool active);

    // Called by the kwin-vr-custodian service when it has matched a profile to
    // hardware and the OpenXR runtime is ready. The plugin looks up the profile
    // by name, finds the output by name, and calls activateForProfile().
    Q_SCRIPTABLE void requestActivateProfile(const QString &profileName,
                                             const QString &outputName);

    // Called by the kwin-vr-custodian service to deactivate VR.
    Q_SCRIPTABLE void requestDeactivate();

    // D-Bus method called by vr-link-monitor (system service) when a DP link
    // is found to be operating below its verified quality baseline.
    Q_SCRIPTABLE void notifyLinkDegraded(const QString &connector, int lanes,
                                         const QString &rateHex);

Q_SIGNALS:
    void vrActiveChanged();

private:
    void onActivateVr(bool checked);

    void start();
    void stop();

    void showNotification(const QString &title, const QString &text,
                          KNotification::NotificationFlags flags);
    void closeNotification();

    void registerDBusService();

    // Output hot-plug monitoring
    void setupOutputMonitoring();
    void setupServiceWatcher();
    void scheduleOutputCheck(Output *output, bool isHotPlug);
    void watchOutputModes(Output *output);
    void checkOutputMode(Output *output);
    void onOutputAdded(Output *output);
    void onOutputRemoved(Output *output);

    // Profile matching
    std::optional<VrProfile> matchDisplayProfile(Output *output) const;
    bool isOutputInSbsMode(Output *output) const;

    // Start VR for a given profile; handles Monado/WiVRn runtime selection.
    void activateForProfile(const VrProfile &profile, Output *output);

    // Service-type VR management
    void onServiceRegistered(const QString &service);
    void onServiceUnregistered(const QString &service);
    void maybeRestoreServiceVr();

    bool m_active = false;
    QQmlApplicationEngine *m_engine = nullptr;
    KwinVrBridge m_vrbridge;
    OpenXRTest m_xrTest;
    KConfigWatcher::Ptr m_watcher;
    KNotification *m_notification = nullptr;

    QList<VrProfile> m_profiles;
    Output *m_vrOutput = nullptr; // Output that triggered current display VR session
    std::optional<VrProfile> m_activeProfile; // Profile driving the current VR session
    QSet<Output *> m_watchedOutputs; // Outputs we are watching for SBS mode changes

    // Service watcher for service-type profiles (WiVRn etc.)
    QDBusServiceWatcher *m_serviceWatcher = nullptr;

    // Watchdog: periodically checks Monado PID; detects restarts that break the XR session
    QTimer *m_watchdogTimer = nullptr;
    qint64 m_monadoPidAtVrStart = -1; // Monado PID recorded when VR session started
    // If set when engine is destroyed, retry setVrActive(true) on this output
    Output *m_retryOutput = nullptr;
    // Tracks whether hideCursor() was called so stop() only calls showCursor() when needed
    bool m_cursorHidden = false;
    // Persistent watcher: any new "openxr" window during the VR session gets steered to the VR output.
    // Remains connected for the full VR session to handle Monado restarts.
    QMetaObject::Connection m_monadoWindowConnection;
    // One-shot: corrects the output after Monado's set_fullscreen(NULL) is processed by KWin.
    QMetaObject::Connection m_monadoFsConnection;

    // Custodian D-Bus presence tracking.
    // When VR stops, the plugin must call vrStopped() on the custodian so the
    // custodian knows it is safe to stop the OpenXR runtime (stopping Monado
    // while the display is still in SBS mode causes an NVIDIA GPU deadlock).
    QDBusServiceWatcher *m_custodianWatcher = nullptr;
    bool m_custodianAvailable = false;

    /** Send vrStopped() to the custodian if it is on D-Bus. */
    void notifyCustodianVrStopped();
};
} // namespace KWin

#endif // KWINVR_H
