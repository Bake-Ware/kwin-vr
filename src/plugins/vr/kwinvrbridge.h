/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVRBRIDGE_H
#define KWINVRBRIDGE_H

#include <QObject>
#include <QQmlEngine>

class KwinVrBridge : public QObject
{
    Q_OBJECT
public:
    explicit KwinVrBridge(QObject *parent = nullptr);

    // Called from QML's health-ping timer; resets the watchdog in kwinvr.cpp
    Q_INVOKABLE void xrPing();

Q_SIGNALS:
    void xrFailed(const QString &errorString);
    void xrPingReceived();
};

#endif // KWINVRBRIDGE_H
