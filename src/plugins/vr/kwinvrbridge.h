/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QQmlEngine>

namespace KWin
{

class KwinVrBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    static KwinVrBridge *instance();
    static KwinVrBridge *create(QQmlEngine *, QJSEngine *)
    {
        auto bridge = instance();
        QQmlEngine::setObjectOwnership(bridge, QQmlEngine::CppOwnership);
        return bridge;
    }

Q_SIGNALS:
    void xrFailed(const QString &errorString);

private:
    explicit KwinVrBridge(QObject *parent = nullptr);
};

} // namespace KWin
