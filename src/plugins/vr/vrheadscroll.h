/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QPointer>
#include <QQuaternion>
#include <QVector2D>
#include <QtQuick3D/private/qquick3dnode_p.h>

namespace KWin
{

class VrHeadScroll : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuick3DNode *camera READ camera WRITE setCamera NOTIFY cameraChanged FINAL)
    Q_PROPERTY(bool headScrollActive READ headScrollActive WRITE setHeadScrollActive NOTIFY headScrollActiveChanged FINAL)
    Q_PROPERTY(float verticalScrollMultiplier READ verticalScrollMultiplier WRITE setVerticalScrollMultiplier NOTIFY verticalScrollMultiplierChanged FINAL)
    Q_PROPERTY(float horizontalScrollMultiplier READ horizontalScrollMultiplier WRITE setHorizontalScrollMultiplier NOTIFY horizontalScrollMultiplierChanged FINAL)
    Q_PROPERTY(float threshold READ threshold WRITE setThreshold NOTIFY thresholdChanged FINAL)

public:
    explicit VrHeadScroll(QObject *parent = nullptr);

    QQuick3DNode *camera() const;
    void setCamera(QQuick3DNode *newCamera);

    bool headScrollActive() const;
    void setHeadScrollActive(bool newHeadScrollActive);

    float verticalScrollMultiplier() const;
    void setVerticalScrollMultiplier(float newVerticalScrollMultiplier);

    float horizontalScrollMultiplier() const;
    void setHorizontalScrollMultiplier(float newHorizontalScrollMultiplier);

    float threshold() const;
    void setThreshold(float newThresholdDegrees);

Q_SIGNALS:
    void cameraChanged();
    void headScrollActiveChanged();
    void verticalScrollMultiplierChanged();
    void horizontalScrollMultiplierChanged();
    void thresholdChanged();
    void wheel(QVector2D delta);

private:
    void calcHeadScroll();

    QPointer<QQuick3DNode> m_camera = nullptr;
    bool m_headScrollActive = false;
    float m_verticalScrollMultiplier = 40.0f;
    float m_horizontalScrollMultiplier = 40.0f;

    QQuaternion m_initialRotation;
    float m_lastVAngle = 0.0f;
    float m_lastHAngle = 0.0f;
    float m_threshold = 0.002f; // ~0.1 degrees in radians
};

} // namespace KWin
