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
    Q_PROPERTY(bool hasPhysicalPrimary READ hasPhysicalPrimary WRITE setHasPhysicalPrimary NOTIFY hasPhysicalPrimaryChanged)
public:
    explicit KwinVrBridge(QObject *parent = nullptr);

    // Called from QML's health-ping timer; resets the watchdog in kwinvr.cpp
    Q_INVOKABLE void xrPing();

    bool hasPhysicalPrimary() const
    {
        return m_hasPhysicalPrimary;
    }
    void setHasPhysicalPrimary(bool v)
    {
        if (m_hasPhysicalPrimary == v)
            return;
        m_hasPhysicalPrimary = v;
        Q_EMIT hasPhysicalPrimaryChanged();
    }

Q_SIGNALS:
    void xrFailed(const QString &errorString);
    void xrPingReceived();
    void hasPhysicalPrimaryChanged();

private:
    bool m_hasPhysicalPrimary = false;
};

#endif // KWINVRBRIDGE_H
