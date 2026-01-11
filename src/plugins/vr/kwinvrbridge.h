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

Q_SIGNALS:
    void xrFailed(const QString &errorString);
};

#endif // KWINVRBRIDGE_H
