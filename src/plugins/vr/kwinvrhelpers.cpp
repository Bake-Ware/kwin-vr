/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <epoxy/gl.h>

#include "kwinvrhelpers.h"

#include "compositor.h"
#include "core/graphicsbuffer.h"
#include "core/outputbackend.h"
#include "core/outputconfiguration.h"
#include "core/renderbackend.h"
#include "cursor.h"
#include "cursorsource.h"
#include "effect/effect.h"
#include "effect/effecthandler.h"
#include "input.h"
#include "kwingraphicshelpers.h"
#include "kwinvr_logging.h"
#include "opengl/eglcontext.h"
#include "opengl/egldisplay.h"
#include "scene/decorationitem.h"
#include "scene/scene.h"
#include "scene/windowitem.h"
#include "scene/workspacescene.h"
#if __has_include("core/drm_formats.h")
#include "core/drm_formats.h"
#else
#include "utils/drm_format_helper.h"
#endif
#include "wayland/plasmawindowmanagement.h"
#include "wayland/surface.h"
#include "wayland_server.h"
#include "waylandwindow.h"
#include "window.h"
#include "workspace.h"
#include "xdgshellwindow.h"

#include <QQmlProperty>
#include <QQuick3DObject>
#include <QQuickItem>
#include <QSGSimpleTextureNode>

#include <drm/drm_fourcc.h>
#include <rhi/qrhi.h>

// Private Qt headers
#include <QtQuick3D/private/qquick3dquaternionutils_p.h>
#include <QtQuick3DXr/private/qquick3dxrmanager_openxr_p.h>
#include <QtQuick3DXr/private/qquick3dxrmanager_p.h>

namespace KWin
{
KwinVrHelpers::KwinVrHelpers(QObject *parent)
    : QObject(parent)
{
    if (auto *ws = WaylandServer::self()) {
        connect(ws, &WaylandServer::lockStateChanged, this, &KwinVrHelpers::screenLockedChanged);
    }
}

void KwinVrHelpers::setDmabufFormatFilterForQt(bool enabled)
{
    if (auto *compositor = Compositor::self()) {
        if (auto *backend = compositor->backend()) {
            backend->setDmabufFeedbackFormatFilter(enabled ? supportedDmabufFormats() : QList<uint32_t>{});
        }
    }
}

bool KwinVrHelpers::isScreenLocked() const
{
    if (auto *ws = WaylandServer::self()) {
        return ws->isScreenLocked();
    }
    return false;
}

void KwinVrHelpers::activateOutput(BackendOutput *o, qreal scale)
{
    OutputConfiguration config;
    config.changeSet(o)->enabled = true;
    auto cnt = Workspace::self()->outputs().size();

    config.changeSet(o)->scale = scale;

    if (cnt == 1 && Workspace::self()->outputs()[0]->backendOutput() == o) {
        qCWarning(KWINVR) << "VR output is the last active output, setting 0,0";
        config.changeSet(o)->pos = QPoint(0, 0);
    } else {
        qCWarning(KWINVR) << "Setting VR output pos to 3000,3000";
        config.changeSet(o)->pos = QPoint(3000, 3000);
    }
    Workspace::self()->applyOutputConfiguration(config);
}

SurfaceInterface *KwinVrHelpers::winGetSurf(Window *window)
{
    auto surface = window->surface();
    if (surface) {
        QJSEngine::setObjectOwnership(surface, QJSEngine::CppOwnership);
    }
    return surface;
}

int KwinVrHelpers::surfaceIndex(SurfaceInterface *surface)
{
    return surface ? surface->below().size() : 0;
}

void KwinVrHelpers::windowOffscreenRef(Window *window, bool ref)
{
    if (ref) {
        window->refOffscreenRendering();
    } else {
        window->unrefOffscreenRendering();
    }
}

bool KwinVrHelpers::windowIsInternal(Window *window)
{
    return window && window->isInternal();
}

void KwinVrHelpers::windowMove(Window *window, const QPointF &topLeft)
{
    if (window) {
        window->move(topLeft);
    }
}

void KwinVrHelpers::windowResize(Window *window, qreal dw, qreal dh)
{
    if (!window) {
        return;
    }
    const auto geo = window->frameGeometry();
    const QSizeF newSize(qMax(1.0, geo.width() + dw), qMax(1.0, geo.height() + dh));
    window->resize(newSize);
}

QSizeF KwinVrHelpers::windowSize(Window *window)
{
    if (!window) {
        return QSizeF();
    }
    return window->frameGeometry().size();
}

bool KwinVrHelpers::keyMatch(int key, int modifiers, const QString &binding)
{
    if (binding.isEmpty() || binding == "none") {
        return false;
    }

    QKeySequence bindingSeq(binding, QKeySequence::PortableText);
    if (bindingSeq.isEmpty()) {
        return false;
    }

    // QKeySequence from int constructor expects Qt::Key combined with Qt::KeyboardModifiers
    int keyInt = key | modifiers;
    QKeySequence eventSeq(keyInt);

    return bindingSeq.matches(eventSeq) == QKeySequence::ExactMatch;
}

QString KwinVrHelpers::keyToString(int key, int modifiers)
{
    int keyInt = key | modifiers;
    return QKeySequence(keyInt).toString(QKeySequence::PortableText);
}

QString KwinVrHelpers::normalizeKey(const QString &binding)
{
    if (binding.isEmpty()) {
        return QString();
    }
    return QKeySequence(binding, QKeySequence::PortableText).toString(QKeySequence::PortableText);
}

IntersectionResult KwinVrHelpers::rayPlaneIntersection(
    const QVector3D &rayOrigin, const QVector3D &rayDirection,
    const QVector3D &planeCenter, const QVector3D &planeNormal)
{
    auto denom = QVector3D::dotProduct(rayDirection, planeNormal);
    if (std::abs(denom) < std::numeric_limits<decltype(denom)>::epsilon()) {
        return {};
    }

    auto diff = planeCenter - rayOrigin;
    auto t = QVector3D::dotProduct(diff, planeNormal) / denom;
    if (t < 0) {
        return {};
    }

    return IntersectionResult{
        true,
        rayOrigin + (rayDirection * t),
        t};
}

IntersectionResult KwinVrHelpers::rayPlaneIntersection(const QQuick3DNode *source, const QQuick3DNode *target)
{
    auto sourcePosition = source->scenePosition();
    auto sourceForward = source->forward();
    auto planeCenter = target->scenePosition();
    auto planeNormal = target->mapDirectionToScene({0, 0, 1});
    planeNormal.normalize();

    return rayPlaneIntersection(sourcePosition, sourceForward, planeCenter, planeNormal);
}

// Returns a quaternion that can be used to rotate source to get destination
QQuaternion KwinVrHelpers::getRotationDelta(const QQuaternion &source, const QQuaternion &destination)
{
    return source.inverted() * destination;
}

QQuaternion KwinVrHelpers::getNodesSceneRotationDelta(const QQuick3DNode *source, const QQuick3DNode *destination)
{
    return getRotationDelta(source->sceneRotation(), destination->sceneRotation());
}

QQuaternion KwinVrHelpers::sceneRotationToNodeRotation(const QQuick3DNode *node, const QQuaternion &sceneRotation)
{
    if (auto parent = qobject_cast<QQuick3DNode *>(node->parentItem())) {
        return getRotationDelta(parent->sceneRotation(), sceneRotation);
    }
    return sceneRotation;
}

QQuaternion KwinVrHelpers::targetSceneRotationToNodeRotation(const QQuick3DNode *node, const QQuick3DNode *targetNode)
{
    return sceneRotationToNodeRotation(node, targetNode->sceneRotation());
}

void KwinVrHelpers::setNodeRotationFromScene(QQuick3DNode *node, const QQuaternion &sceneRotation)
{
    node->setRotation(sceneRotationToNodeRotation(node, sceneRotation));
}

void KwinVrHelpers::setNodePositionFromScene(QQuick3DNode *node, const QVector3D &scenePosition)
{
    auto targetParent = qobject_cast<QQuick3DNode *>(node->parentNode());
    if (!targetParent) {
        return;
    }

    const auto newPosition = targetParent->mapPositionFromScene(scenePosition);
    QQmlProperty::write(node, "position", newPosition);
}

QQuaternion KwinVrHelpers::rotationToFaceDirection(const QVector3D &forward,
                                                   const QQuaternion &referenceRotation)
{
    constexpr float epsilon = 1e-6f;

    // Get reference frame vectors for roll alignment
    const QVector3D refUp = referenceRotation.rotatedVector(QVector3D(0, 1, 0));

    // Construct orthonormal basis
    QVector3D right;
    const float upDotForward = std::abs(QVector3D::dotProduct(refUp, forward));

    if (upDotForward > 0.9999f) {
        // Edge case: looking straight up or down (forward parallel to refUp)
        // Use reference right vector as fallback
        const QVector3D refRight = referenceRotation.rotatedVector(QVector3D(1, 0, 0));
        right = QVector3D::crossProduct(forward, refRight).normalized();

        // If still degenerate, use reference forward
        if (right.lengthSquared() < epsilon) {
            const QVector3D refForward = referenceRotation.rotatedVector(QVector3D(0, 0, -1));
            right = QVector3D::crossProduct(forward, refForward).normalized();
        }
    } else {
        // Normal case
        right = QVector3D::crossProduct(forward, refUp).normalized();
    }

    // Reconstruct up to ensure orthogonality
    const QVector3D up = QVector3D::crossProduct(right, forward).normalized();

    // Build rotation matrix: columns are new axes
    // X = right, Y = up, Z = -forward (Qt Quick 3D: -Z is forward)
    QMatrix3x3 mat;
    mat(0, 0) = right.x();
    mat(0, 1) = up.x();
    mat(0, 2) = -forward.x();

    mat(1, 0) = right.y();
    mat(1, 1) = up.y();
    mat(1, 2) = -forward.y();

    mat(2, 0) = right.z();
    mat(2, 1) = up.z();
    mat(2, 2) = -forward.z();

    return QQuaternion::fromRotationMatrix(mat);
}

QVector3D KwinVrHelpers::rotateVector(const QQuaternion &rotation, const QVector3D &vector)
{
    return rotation.rotatedVector(vector);
}

QVector2D KwinVrHelpers::raySphereIntersect(const QVector3D &rayOrigin,
                                            const QVector3D &rayDirection,
                                            const QVector3D &sphereCenter,
                                            float sphereRadius)
{
    // Ray: P = rayOrigin + t * rayDirection
    // Sphere: |P - sphereCenter|² = sphereRadius²
    // Substituting: |rayOrigin + t * rayDirection - sphereCenter|² = sphereRadius²
    // Let v = rayOrigin - sphereCenter
    // |v + t * rayDirection|² = r²
    // v·v + 2*t*(v·rayDirection) + t²*(rayDirection·rayDirection) = r²
    // For normalized rayDirection: t² + 2*t*(v·d) + v·v - r² = 0

    const QVector3D v = rayOrigin - sphereCenter;
    const float vDotD = QVector3D::dotProduct(v, rayDirection);
    const float vDotV = QVector3D::dotProduct(v, v);
    const float r = sphereRadius;

    // Quadratic coefficients: at² + bt + c = 0
    // a = 1 (assuming normalized direction), b = 2*vDotD, c = vDotV - r²
    const float b = 2.0f * vDotD;
    const float c = vDotV - r * r;
    const float discriminant = b * b - 4.0f * c;

    if (discriminant < 0.0f) {
        return QVector2D(-1.0f, -1.0f); // No intersection
    }

    const float sqrtDisc = std::sqrt(discriminant);
    const float t1 = (-b - sqrtDisc) / 2.0f;
    const float t2 = (-b + sqrtDisc) / 2.0f;

    return QVector2D(t1, t2);
}

float KwinVrHelpers::raySphereIntersectFar(const QVector3D &rayOrigin,
                                           const QVector3D &rayDirection,
                                           const QVector3D &sphereCenter,
                                           float sphereRadius)
{
    const QVector2D intersections = raySphereIntersect(rayOrigin, rayDirection, sphereCenter, sphereRadius);
    const float t1 = intersections.x();
    const float t2 = intersections.y();

    if (t2 > 0.0f) {
        return t2;
    }
    if (t1 > 0.0f) {
        return t1;
    }

    return -1.0f;
}

QQuaternion KwinVrHelpers::rotationBetweenVectors(const QVector3D &from, const QVector3D &to)
{
    const QVector3D fromNorm = from.normalized();
    const QVector3D toNorm = to.normalized();

    const float dot = QVector3D::dotProduct(fromNorm, toNorm);

    // Vectors are parallel (same direction)
    if (dot > 0.999999f) {
        return QQuaternion();
    }

    // Vectors are anti-parallel (opposite direction)
    if (dot < -0.9999f) {
        // Find an orthogonal axis
        QVector3D axis = QVector3D::crossProduct(fromNorm, QVector3D(1, 0, 0));
        if (axis.lengthSquared() < 0.0001f) {
            axis = QVector3D::crossProduct(fromNorm, QVector3D(0, 1, 0));
        }
        return QQuaternion::fromAxisAndAngle(axis.normalized(), 180.0f);
    }

    const QVector3D axis = QVector3D::crossProduct(fromNorm, toNorm);
    const float angle = std::acos(std::clamp(dot, -1.0f, 1.0f)) * 180.0f / float(M_PI);

    return QQuaternion::fromAxisAndAngle(axis.normalized(), angle);
}

QQuaternion KwinVrHelpers::rotationBetweenVectorsKeepRoll(const QVector3D &from,
                                                          const QVector3D &to,
                                                          const QQuaternion &referenceRotation)
{
    constexpr float epsilon = 1e-6f;

    const QVector3D fromNorm = from.normalized();
    const QVector3D toNorm = to.normalized();

    if (fromNorm.lengthSquared() < epsilon || toNorm.lengthSquared() < epsilon) {
        return QQuaternion();
    }

    const QVector3D referenceUp = referenceRotation.rotatedVector(QVector3D(0, 1, 0));
    const QVector3D referenceRight = referenceRotation.rotatedVector(QVector3D(1, 0, 0));
    const QVector3D referenceForward = referenceRotation.rotatedVector(QVector3D(0, 0, -1));

    auto buildRotation = [&](const QVector3D &forward) -> QQuaternion {
        QVector3D right = QVector3D::crossProduct(forward, referenceUp);
        if (right.lengthSquared() < epsilon) {
            right = QVector3D::crossProduct(forward, referenceRight);
            if (right.lengthSquared() < epsilon) {
                right = QVector3D::crossProduct(forward, referenceForward);
            }
        }

        right.normalize();
        const QVector3D up = QVector3D::crossProduct(right, forward).normalized();

        QMatrix3x3 mat;
        mat(0, 0) = right.x();
        mat(0, 1) = up.x();
        mat(0, 2) = -forward.x();

        mat(1, 0) = right.y();
        mat(1, 1) = up.y();
        mat(1, 2) = -forward.y();

        mat(2, 0) = right.z();
        mat(2, 1) = up.z();
        mat(2, 2) = -forward.z();

        return QQuaternion::fromRotationMatrix(mat);
    };

    const QQuaternion fromRotation = buildRotation(fromNorm);
    const QQuaternion toRotation = buildRotation(toNorm);
    return toRotation * fromRotation.inverted();
}

QQuaternion KwinVrHelpers::rotationBetweenVectorsPreserveRoll(const QVector3D &from,
                                                              const QVector3D &to,
                                                              const QQuaternion &currentRotation,
                                                              const QQuaternion &referenceRotation)
{
    // Step 1: Compute base rotation using cross-product
    const QQuaternion qBase = rotationBetweenVectors(from, to);

    // Step 2: Get current up from currentRotation
    const QVector3D currentUp = currentRotation.rotatedVector(QVector3D(0, 1, 0));

    // Step 3: Measure roll before rotation (around 'from' direction)
    const float rollBefore = rollAngleBetween(referenceRotation, from, currentUp);

    // Step 4: Compute what up would be after base rotation
    const QVector3D newUp = qBase.rotatedVector(currentUp);

    // Step 5: Measure roll after base rotation (around 'to' direction)
    const float rollAfter = rollAngleBetween(referenceRotation, to, newUp);

    // Step 6: Compute roll correction needed
    const float rollCorrection = rollBefore - rollAfter;

    // Step 7: Create correction rotation around 'to' direction (preserves from->to mapping)
    const QQuaternion qCorrection = QQuaternion::fromAxisAndAngle(to, rollCorrection);

    // Step 8: Return combined rotation (correction applied after base)
    return qCorrection * qBase;
}

float KwinVrHelpers::rollAngleBetweenUp(const QVector3D &referenceUp,
                                        const QVector3D &forwardDirection,
                                        const QVector3D &currentUp)
{
    constexpr float epsilon = 1e-6f;

    const QVector3D forward = forwardDirection.normalized();

    if (forward.lengthSquared() < epsilon) {
        return 0.0f;
    }

    const QVector3D refUpProj = referenceUp - forward * QVector3D::dotProduct(referenceUp, forward);
    const QVector3D upProj = currentUp - forward * QVector3D::dotProduct(currentUp, forward);

    if (refUpProj.lengthSquared() < epsilon || upProj.lengthSquared() < epsilon) {
        return 0.0f;
    }

    const QVector3D refUpNorm = refUpProj.normalized();
    const QVector3D upNorm = upProj.normalized();
    const float dot = std::clamp(QVector3D::dotProduct(refUpNorm, upNorm), -1.0f, 1.0f);
    const float angle = std::acos(dot) * 180.0f / float(M_PI);
    const QVector3D cross = QVector3D::crossProduct(refUpNorm, upNorm);
    const float sign = QVector3D::dotProduct(cross, forward) < 0.0f ? -1.0f : 1.0f;
    return angle * sign;
}

float KwinVrHelpers::rollAngleBetween(const QQuaternion &referenceRotation,
                                      const QVector3D &forwardDirection,
                                      const QVector3D &currentUp)
{
    const QVector3D referenceUp = referenceRotation.rotatedVector(QVector3D(0, 1, 0));
    return rollAngleBetweenUp(referenceUp, forwardDirection, currentUp);
}

float KwinVrHelpers::rollAngleBetween(const QQuaternion &referenceRotation,
                                      const QQuaternion &currentRotation)
{
    const QVector3D forward = currentRotation.rotatedVector(QVector3D(0, 0, -1));
    const QVector3D up = currentRotation.rotatedVector(QVector3D(0, 1, 0));
    return rollAngleBetween(referenceRotation, forward, up);
}

float KwinVrHelpers::rollAngleBetween(const QQuaternion &referenceRotation,
                                      const QQuaternion &currentRotation,
                                      const QVector3D &forwardDirection)
{
    const QVector3D up = currentRotation.rotatedVector(QVector3D(0, 1, 0));
    return rollAngleBetween(referenceRotation, forwardDirection, up);
}

RelativePose KwinVrHelpers::rotateRelativePose(const RelativePose &pose,
                                               const QQuaternion &rotation)
{
    return RelativePose(rotation * pose.rotation,
                        rotation.rotatedVector(pose.position));
}

// Helper: Rotates node to face along 'forward' direction, using 'referenceRotation'
// to derive up vector for roll alignment and fallback vectors for edge cases.
static void rotateNodeToFaceDirection(QQuick3DNode *node,
                                      const QVector3D &forward,
                                      const QQuaternion &referenceRotation)
{
    const QQuaternion sceneRotation = KwinVrHelpers::rotationToFaceDirection(forward, referenceRotation);
    KwinVrHelpers::setNodeRotationFromScene(node, sceneRotation);
}

void KwinVrHelpers::turnToFace(QQuick3DNode *node, const QQuick3DNode *target)
{
    if (!node || !target) {
        return;
    }

    const QVector3D fromTarget = node->scenePosition() - target->scenePosition();

    // Handle degenerate case: same position
    if (fromTarget.lengthSquared() < 1e-6f) {
        setNodeRotationFromScene(node, target->sceneRotation());
        return;
    }

    // Use target's rotation for roll alignment
    rotateNodeToFaceDirection(node, fromTarget.normalized(), target->sceneRotation());
}

void KwinVrHelpers::turnToFaceKeepRoll(QQuick3DNode *node, const QQuick3DNode *target)
{
    if (!node || !target) {
        return;
    }

    const QVector3D fromTarget = node->scenePosition() - target->scenePosition();

    // Handle degenerate case: same position - keep current rotation
    if (fromTarget.lengthSquared() < 1e-6f) {
        return;
    }

    // Use node's current rotation to preserve roll
    rotateNodeToFaceDirection(node, fromTarget.normalized(), node->sceneRotation());
}

RelativePose KwinVrHelpers::getRelativePose(QQuick3DNode *node, const QQuick3DNode *target)
{
    return RelativePose(getNodesSceneRotationDelta(node, target),
                        node->mapPositionFromScene(target->scenePosition()));
}

void KwinVrHelpers::applyRelativePose(const QQuick3DNode *node, QQuick3DNode *target, const RelativePose &pose)
{
    auto targetParent = qobject_cast<QQuick3DNode *>(target->parentNode());
    if (!targetParent) {
        qCWarning(KWINVR) << "Target node has no parent node while applying relative pose";
        return;
    }

    const auto newPosition = node->mapPositionToNode(targetParent, pose.position);
    QQmlProperty::write(target, "position", newPosition);

    const auto newRotation = sceneRotationToNodeRotation(target, node->sceneRotation() * pose.rotation);
    QQmlProperty::write(target, "rotation", newRotation);
}

RelativePose KwinVrHelpers::relativePoseToScenePose(const QQuick3DNode *node, const RelativePose &pose)
{
    if (!node) {
        return RelativePose();
    }

    return RelativePose(node->sceneRotation() * pose.rotation,
                        node->mapPositionToScene(pose.position));
}

RelativePose KwinVrHelpers::relativePoseToRelativePose(const QQuick3DNode *currentNode,
                                                       const QQuick3DNode *newNode,
                                                       const RelativePose &pose)
{
    if (!currentNode || !newNode) {
        return RelativePose();
    }

    return RelativePose(relativeRotationToRelativeRotation(currentNode, newNode, pose.rotation),
                        newNode->mapPositionFromNode(currentNode, pose.position));
}

QQuaternion KwinVrHelpers::relativeRotationToRelativeRotation(const QQuick3DNode *currentNode,
                                                              const QQuick3DNode *newNode,
                                                              const QQuaternion &rotation)
{
    if (!currentNode || !newNode) {
        return QQuaternion();
    }

    const QQuaternion currentSceneRotation = currentNode->sceneRotation();
    return getRotationDelta(newNode->sceneRotation(), currentSceneRotation * rotation);
}

} // namespace KWin
