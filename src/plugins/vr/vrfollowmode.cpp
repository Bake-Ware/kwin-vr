/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrfollowmode.h"
#include "kwinvrhelpers.h"

#include <QtMath>
#include <limits>

namespace KWin
{

VrFollowMode::VrFollowMode(QObject *parent)
    : QObject(parent)
{
    m_frameTimer.setInterval(16);
    connect(&m_frameTimer, &QTimer::timeout, this, &VrFollowMode::onFrame);
}

QQuick3DNode *VrFollowMode::camera() const
{
    return m_camera;
}

void VrFollowMode::setCamera(QQuick3DNode *camera)
{
    if (m_camera == camera) {
        return;
    }

    if (m_camera) {
        disconnect(m_camera, &QObject::destroyed, this, nullptr);
    }

    m_camera = camera;

    if (m_camera) {
        connect(m_camera, &QObject::destroyed, this, [this]() {
            setCamera(nullptr);
        });
    }

    updateConnections();
    Q_EMIT cameraChanged();
}

QQuick3DNode *VrFollowMode::rotationTarget() const
{
    return m_rotationTarget;
}

void VrFollowMode::setRotationTarget(QQuick3DNode *rotationTarget)
{
    if (m_rotationTarget == rotationTarget) {
        return;
    }

    if (m_rotationTarget) {
        disconnect(m_rotationTarget, &QObject::destroyed, this, nullptr);
    }

    m_rotationTarget = rotationTarget;

    if (m_rotationTarget) {
        connect(m_rotationTarget, &QObject::destroyed, this, [this]() {
            setRotationTarget(nullptr);
        });
    }

    updateConnections();
    Q_EMIT rotationTargetChanged();
}

bool VrFollowMode::worldUpAlignment() const
{
    return m_worldUpAlignment;
}

void VrFollowMode::setFovH(int fovH)
{
    if (m_fovH == fovH) {
        return;
    }
    m_fovH = fovH;
    Q_EMIT fovHChanged();
}

int VrFollowMode::fovV() const
{
    return m_fovV;
}

void VrFollowMode::setFovV(int fovV)
{
    if (m_fovV == fovV) {
        return;
    }
    m_fovV = fovV;
    Q_EMIT fovVChanged();
}

int VrFollowMode::stopFovH() const
{
    return m_stopFovH;
}

void VrFollowMode::setStopFovH(int stopFovH)
{
    if (m_stopFovH == stopFovH) {
        return;
    }
    m_stopFovH = stopFovH;
    Q_EMIT stopFovHChanged();
}

int VrFollowMode::stopFovV() const
{
    return m_stopFovV;
}

void VrFollowMode::setStopFovV(int stopFovV)
{
    if (m_stopFovV == stopFovV) {
        return;
    }
    m_stopFovV = stopFovV;
    Q_EMIT stopFovVChanged();
}

bool VrFollowMode::active() const
{
    return m_active;
}

void VrFollowMode::setActive(bool active)
{
    if (m_active == active) {
        return;
    }
    m_active = active;
    Q_EMIT activeChanged();
}

double VrFollowMode::delay() const
{
    return m_delay;
}

void VrFollowMode::setDelay(double delay)
{
    if (qFuzzyCompare(m_delay, delay)) {
        return;
    }
    m_delay = delay;
    Q_EMIT delayChanged();
}

double VrFollowMode::speed() const
{
    return m_speed;
}

void VrFollowMode::setSpeed(double speed)
{
    if (qFuzzyCompare(m_speed, speed)) {
        return;
    }
    m_speed = speed;
    Q_EMIT speedChanged();
}

void VrFollowMode::setWorldUpAlignment(bool worldUpAlignment)
{
    if (m_worldUpAlignment == worldUpAlignment) {
        return;
    }
    m_worldUpAlignment = worldUpAlignment;
    Q_EMIT worldUpAlignmentChanged();
}

int VrFollowMode::fovH() const
{
    return m_fovH;
}

void VrFollowMode::registerObject(QQuick3DNode *node)
{
    if (!node || m_trackedNodes.contains(node)) {
        return;
    }

    m_trackedNodes.append(node);

    connect(node, &QObject::destroyed, this, [this, node]() {
        m_trackedNodes.removeAll(node);
    });
}

void VrFollowMode::unregisterObject(QQuick3DNode *node)
{
    m_trackedNodes.removeAll(node);
    if (node == m_focusOverride) {
        clearFocusOverride();
    }
    if (node) {
        disconnect(node, &QObject::destroyed, this, nullptr);
    }
}

void VrFollowMode::focusOn(QQuick3DNode *node, QQuick3DNode *camera)
{
    if (!node || !camera || !m_rotationTarget) {
        return;
    }
    if (!node->visible()) {
        return;
    }

    if (m_focusOverride && m_focusOverride != node) {
        clearFocusOverride();
    }
    m_focusOverride = node;
    m_focusCamera = camera;
    // Dedicated connection handles: a blanket disconnect(node, ...) would
    // also kill the tracked-node cleanup registerObject installed.
    m_focusNodeDestroyed = connect(node, &QObject::destroyed, this, [this]() {
        m_focusOverride = nullptr;
        clearFocusOverride();
    });
    m_focusCameraDestroyed = connect(camera, &QObject::destroyed, this, [this]() {
        m_focusCamera = nullptr;
        clearFocusOverride();
    });

    // In-FOV test with the override camera in place (m_camera may be
    // null-gated during hover/grab/menu). Already within the reactive
    // FOV — consider it in-frame, nothing to pan.
    const QVector2D angles = anglesToNode(node);
    if (angles.x() <= m_fovH && angles.y() <= m_fovV) {
        clearFocusOverride();
        return;
    }

    // Make sure the frame loop is running — updateConnections would have
    // stopped it when m_camera was null.
    if (!m_frameTimer.isActive()) {
        m_timer.start();
        m_frameTimer.start();
    }

    m_lookAwayTime = 0.0;
    setActive(true);
}

void VrFollowMode::unfocus(QQuick3DNode *node)
{
    if (node && node == m_focusOverride) {
        clearFocusOverride();
    }
}

void VrFollowMode::clearFocusOverride()
{
    disconnect(m_focusNodeDestroyed);
    disconnect(m_focusCameraDestroyed);
    m_focusOverride = nullptr;
    m_focusCamera = nullptr;
    // May need to stop the frame loop again if focusOn started it while
    // the normal camera binding was null-gated.
    updateConnections();
}

QQuick3DNode *VrFollowMode::effectiveCamera() const
{
    return (m_focusOverride && m_focusCamera) ? m_focusCamera : m_camera;
}

void VrFollowMode::updateConnections()
{
    if (m_camera && m_rotationTarget) {
        if (!m_frameTimer.isActive()) {
            m_timer.start();
            m_frameTimer.start();
        }
    } else {
        m_frameTimer.stop();
        m_lookAwayTime = 0.0;
        setActive(false);
    }
}

QVector2D VrFollowMode::anglesToNode(const QQuick3DNode *node) const
{
    QQuick3DNode *camera = effectiveCamera();
    if (!camera || !node) {
        return QVector2D(180, 180);
    }

    const QVector3D toNode = node->scenePosition() - camera->scenePosition();
    const QVector3D localDir = camera->mapDirectionFromScene(toNode).normalized();

    const float hAngle = qAbs(qRadiansToDegrees(qAtan2(localDir.x(), -localDir.z())));
    const float vAngle = qAbs(qRadiansToDegrees(qAtan2(localDir.y(), -localDir.z())));

    return QVector2D(hAngle, vAngle);
}

bool VrFollowMode::anyNodeInFov() const
{
    for (auto node : m_trackedNodes) {
        if (node && node->visible()) {
            QVector2D angles = anglesToNode(node);
            if (angles.x() <= m_fovH && angles.y() <= m_fovV) {
                return true;
            }
        }
    }
    return false;
}

QQuick3DNode *VrFollowMode::findClosestNode() const
{
    QQuick3DNode *closest = nullptr;
    float minDistSq = std::numeric_limits<float>::max();

    for (auto node : m_trackedNodes) {
        if (node && node->visible()) {
            QVector2D angles = anglesToNode(node);
            float distSq = angles.x() * angles.x() + angles.y() * angles.y();
            if (distSq < minDistSq) {
                minDistSq = distSq;
                closest = node;
            }
        }
    }

    return closest;
}

bool VrFollowMode::isNodeInStopFov(const QQuick3DNode *node) const
{
    if (!node) {
        return false;
    }

    QVector2D angles = anglesToNode(node);
    return angles.x() <= m_stopFovH && angles.y() <= m_stopFovV;
}

void VrFollowMode::onFrame()
{
    // Effective camera: during a focus override, the explicit camera given
    // to focusOn keeps the pan running even while the normal `camera`
    // binding is null-gated (hover/grab/menu).
    if (!effectiveCamera() || !m_rotationTarget) {
        return;
    }

    const double deltaTime = m_timer.elapsed() / 1000.0;
    m_timer.restart();
    const double dt = qMin(deltaTime, 0.1);

    // Override wins over closest while set — a focus-triggered pan must
    // stay locked on its target until centered.
    auto target = (m_focusOverride && m_focusOverride->visible())
        ? m_focusOverride
        : findClosestNode();
    if (!target) {
        return;
    }

    if (m_active) {
        if (isNodeInStopFov(target)) {
            setActive(false);
            m_lookAwayTime = 0.0;
            if (m_focusOverride) {
                // Final re-face: pan is done, lock orientation to cam.
                KwinVrHelpers::turnToFace(m_focusOverride, effectiveCamera());
                clearFocusOverride();
            }
        } else {
            rotateTowardsNode(target, dt);
            if (target == m_focusOverride) {
                // Handle rotation drifts the override's scene rotation; re-face
                // every frame so the window stays normal-to-camera with cam roll.
                KwinVrHelpers::turnToFace(m_focusOverride, effectiveCamera());
            }
        }
    } else {
        if (anyNodeInFov()) {
            m_lookAwayTime = 0.0;
        } else {
            m_lookAwayTime += dt;
            if (m_lookAwayTime > m_delay) {
                setActive(true);
                rotateTowardsNode(target, dt);
            }
        }
    }
}

void VrFollowMode::rotateTowardsNode(QQuick3DNode *node, double dt)
{
    QQuick3DNode *camera = effectiveCamera();
    if (!camera) {
        return;
    }

    // Calculate rotation to bring node into view
    QVector3D toClosest = node->scenePosition() - camera->scenePosition();
    if (toClosest.lengthSquared() < 0.0001f) {
        return;
    }

    toClosest.normalize();
    QVector3D cameraForward = camera->forward().normalized();

    // Delta rotation to bring the closest window into camera's forward direction
    QQuaternion deltaRotation = QQuaternion::rotationTo(toClosest, cameraForward);

    // Current state in scene space
    QVector3D currentScenePos = m_rotationTarget->scenePosition();
    QQuaternion currentSceneRot = m_rotationTarget->sceneRotation();

    // Pivot point is the camera position - we rotate around the user's head
    QVector3D pivotPoint = camera->scenePosition();

    // Rotate position around pivot
    QVector3D offset = currentScenePos - pivotPoint;
    QVector3D targetOffset = deltaRotation.rotatedVector(offset);
    QVector3D targetScenePos = pivotPoint + targetOffset;

    // Compute target rotation directly (not by composing with current rotation)
    // For the grab handle container, we want its +Z to point toward the camera
    // (so child windows, which face +Z locally, will face the camera)
    // rotationToFaceDirection makes -Z point along 'forward', so we pass the opposite direction
    QVector3D awayFromCamera = (targetScenePos - pivotPoint).normalized();

    // Reference rotation determines up vector for roll alignment
    QQuaternion referenceRot = m_worldUpAlignment ? QQuaternion() : camera->sceneRotation();

    // This makes -Z point away from camera, thus +Z points toward camera
    QQuaternion targetSceneRot = KwinVrHelpers::rotationToFaceDirection(awayFromCamera, referenceRot);

    // Interpolate in scene space
    const float t = qMin(1.0f, static_cast<float>(dt * m_speed));
    QQuaternion newSceneRot = QQuaternion::slerp(currentSceneRot, targetSceneRot, t);

    // Interpolate position along the arc (not linear) to preserve distance from pivot
    QVector3D newScenePos = currentScenePos;
    const float distance = offset.length();
    if (distance > 0.0001f) {
        // Slerp the offset direction while maintaining distance
        QVector3D currentDir = offset.normalized();
        QVector3D targetDir = targetOffset.normalized();
        QQuaternion dirRotation = QQuaternion::rotationTo(currentDir, targetDir);
        QQuaternion interpolatedDirRot = QQuaternion::slerp(QQuaternion(), dirRotation, t);
        QVector3D newDir = interpolatedDirRot.rotatedVector(currentDir);
        newScenePos = pivotPoint + newDir * distance;
    }

    KwinVrHelpers::setNodeRotationFromScene(m_rotationTarget, newSceneRot);
    KwinVrHelpers::setNodePositionFromScene(m_rotationTarget, newScenePos);
}

} // namespace KWin
