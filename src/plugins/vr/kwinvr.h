/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVR_H
#define KWINVR_H

#pragma once

#include <KConfigWatcher>
#include <KNotification>

#include <QKeySequence>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QSet>

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
    void scheduleOutputCheck(Output *output, bool isHotPlug);
    void watchOutputModes(Output *output);
    void checkOutputMode(Output *output);
    void onOutputAdded(Output *output);
    void onOutputRemoved(Output *output);
    std::optional<VrProfile> matchProfile(Output *output) const;

    bool m_active = false;
    QQmlApplicationEngine *m_engine = nullptr;
    KwinVrBridge m_vrbridge;
    OpenXRTest m_xrTest;
    KConfigWatcher::Ptr m_watcher;
    KNotification *m_notification = nullptr;

    QList<VrProfile> m_profiles;
    Output *m_vrOutput = nullptr;       // the output that triggered current VR session
    QSet<Output *> m_watchedOutputs;    // outputs we are watching for SBS mode changes
};
}

#endif // KWINVR_H
