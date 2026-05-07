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
    // True when VR was activated but no DRM lease is open (no HMD in use).
    // QML branches on this to spawn Vr2DViewport instead of XrScene.
    Q_PROPERTY(bool fallbackMode READ fallbackMode WRITE setFallbackMode NOTIFY fallbackModeChanged)
public:
    static KwinVrBridge *instance();
    static KwinVrBridge *create(QQmlEngine *, QJSEngine *)
    {
        auto bridge = instance();
        QQmlEngine::setObjectOwnership(bridge, QQmlEngine::CppOwnership);
        return bridge;
    }

    bool fallbackMode() const;
    void setFallbackMode(bool fallback);

Q_SIGNALS:
    void xrFailed(const QString &errorString);
    void fallbackModeChanged();

private:
    explicit KwinVrBridge(QObject *parent = nullptr);
    bool m_fallbackMode = false;
};

} // namespace KWin
