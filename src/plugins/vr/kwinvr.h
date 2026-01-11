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

#include <plugin.h>

#include "kwinvrbridge.h"
#include "openxrtest.h"

namespace KWin
{

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

    bool m_active = false;
    QQmlApplicationEngine *m_engine = nullptr;
    KwinVrBridge m_vrbridge;
    OpenXRTest m_xrTest;
    KConfigWatcher::Ptr m_watcher;
    KNotification *m_notification = nullptr;
};
}

#endif // KWINVR_H
