/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrheadscroll.h"
#include "kwinvr_logging.h"

#include <algorithm>
#include <cmath>

namespace KWin
{

VrHeadScroll::VrHeadScroll(QObject *parent)
    : QObject(parent)
{
}

QQuick3DNode *VrHeadScroll::camera() const
{
    return m_camera;
}

void VrHeadScroll::setCamera(QQuick3DNode *newCamera)
{
    if (m_camera == newCamera) {
        return;
    }

    if (m_headScrollActive && m_camera) {
        disconnect(m_camera, &QQuick3DNode::rotationChanged, this, &VrHeadScroll::calcHeadScroll);
    }

    m_camera = newCamera;

    if (m_headScrollActive && m_camera) {
        m_initialRotation = m_camera->rotation().inverted();
        m_lastVAngle = 0;
        m_lastHAngle = 0;
        connect(m_camera, &QQuick3DNode::rotationChanged, this, &VrHeadScroll::calcHeadScroll);
    }

    Q_EMIT cameraChanged();
}

bool VrHeadScroll::headScrollActive() const
{
    return m_headScrollActive;
}

void VrHeadScroll::setHeadScrollActive(bool newHeadScrollActive)
{
    if (m_headScrollActive == newHeadScrollActive) {
        return;
    }

    m_headScrollActive = newHeadScrollActive;
    qCDebug(KWINVR) << "head scroll active:" << m_headScrollActive;

    if (m_headScrollActive) {
        if (m_camera) {
            m_initialRotation = m_camera->rotation().inverted();
            m_lastVAngle = 0;
            m_lastHAngle = 0;
            connect(m_camera, &QQuick3DNode::rotationChanged, this, &VrHeadScroll::calcHeadScroll);
        }
    } else {
        if (m_camera) {
            disconnect(m_camera, &QQuick3DNode::rotationChanged, this, &VrHeadScroll::calcHeadScroll);
        }
    }

    Q_EMIT headScrollActiveChanged();
}

float VrHeadScroll::verticalScrollMultiplier() const
{
    return m_verticalScrollMultiplier;
}

void VrHeadScroll::setVerticalScrollMultiplier(float newVerticalScrollMultiplier)
{
    if (qFuzzyCompare(m_verticalScrollMultiplier, newVerticalScrollMultiplier)) {
        return;
    }
    m_verticalScrollMultiplier = newVerticalScrollMultiplier;
    Q_EMIT verticalScrollMultiplierChanged();
}

float VrHeadScroll::horizontalScrollMultiplier() const
{
    return m_horizontalScrollMultiplier;
}

void VrHeadScroll::setHorizontalScrollMultiplier(float newHorizontalScrollMultiplier)
{
    if (qFuzzyCompare(m_horizontalScrollMultiplier, newHorizontalScrollMultiplier)) {
        return;
    }
    m_horizontalScrollMultiplier = newHorizontalScrollMultiplier;
    Q_EMIT horizontalScrollMultiplierChanged();
}

float VrHeadScroll::threshold() const
{
    return qRadiansToDegrees(m_threshold);
}

void VrHeadScroll::setThreshold(float newThresholdDegrees)
{
    const float newThresholdRadians = qDegreesToRadians(newThresholdDegrees);
    if (qFuzzyCompare(m_threshold, newThresholdRadians)) {
        return;
    }
    m_threshold = newThresholdRadians;
    Q_EMIT thresholdChanged();
}

void VrHeadScroll::calcHeadScroll()
{
    if (!m_camera) {
        return;
    }

    const QQuaternion currentRotation = m_camera->rotation();
    const QQuaternion relativeRotation = m_initialRotation * currentRotation;

    // Extract angles via vector projection
    const QVector3D forward = relativeRotation.rotatedVector(QVector3D(0, 0, -1));

    // Pitch: angle from horizontal plane
    const float verticalAngle = std::asin(std::clamp(forward.y(), -1.0f, 1.0f));

    // Yaw: angle in XZ plane
    const float horizontalAngle = std::atan2(forward.x(), -forward.z());

    const float verticalAngleDiff = verticalAngle - m_lastVAngle;
    const float horizontalAngleDiff = horizontalAngle - m_lastHAngle;

    float vdelta = 0.0f;
    if (std::abs(verticalAngleDiff) >= m_threshold) {
        vdelta = -qRadiansToDegrees(verticalAngleDiff) * m_verticalScrollMultiplier;
        m_lastVAngle = verticalAngle;
    }

    float hdelta = 0.0f;
    if (std::abs(horizontalAngleDiff) >= m_threshold) {
        hdelta = qRadiansToDegrees(horizontalAngleDiff) * m_horizontalScrollMultiplier;
        m_lastHAngle = horizontalAngle;
    }

    if (!qFuzzyIsNull(vdelta) || !qFuzzyIsNull(hdelta)) {
        Q_EMIT wheel(QVector2D(vdelta, hdelta));
    }
}

} // namespace KWin
