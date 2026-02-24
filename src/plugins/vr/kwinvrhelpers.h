/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "kwinvirtualscreenhandle.h"
#include "wayland/subcompositor.h"
#include "wayland/surface.h"
#include <KDecoration3/Decoration>
#include <QKeySequence>
#include <QList>
#include <QObject>
#include <QQuickItem>

/* private stuff */
#include <QtQuick3D/private/qquick3dnode_p.h>

#include "kwincompat.h"

namespace KWin
{

class RelativePose
{
    Q_GADGET
    Q_PROPERTY(QQuaternion rotation READ rotation WRITE setRotation)
    Q_PROPERTY(QVector3D position READ position WRITE setPosition)
    QML_VALUE_TYPE(relativePose)

public:
    RelativePose() = default;
    RelativePose(const QQuaternion &rotation, const QVector3D &position)
        : m_rotation(rotation)
        , m_position(position)
    {
    }

    QQuaternion rotation() const
    {
        return m_rotation;
    }
    void setRotation(const QQuaternion &newRotation)
    {
        m_rotation = newRotation;
    }

    QVector3D position() const
    {
        return m_position;
    }
    void setPosition(const QVector3D &newPosition)
    {
        m_position = newPosition;
    }

private:
    QQuaternion m_rotation;
    QVector3D m_position;
};

class IntersectionResult
{
    Q_GADGET
    Q_PROPERTY(bool valid READ valid)
    Q_PROPERTY(QVector3D position READ position)
    Q_PROPERTY(float distance READ distance)
    QML_VALUE_TYPE(intersectionResult)
public:
    bool valid() const
    {
        return m_valid;
    }
    QVector3D position()
    {
        return m_position;
    }
    float distance()
    {
        return m_distance;
    }
    bool m_valid = false;
    QVector3D m_position;
    float m_distance = 0;
};

class Window;
// class BackendOutput;
class KwinVrHelpers : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool screenLocked READ isScreenLocked NOTIFY screenLockedChanged)
    Q_PROPERTY(KWin::Window *forcedFocusWindow READ forcedFocusWindow WRITE setForcedFocusWindow NOTIFY forcedFocusWindowChanged FINAL)
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit KwinVrHelpers(QObject *parent = nullptr);
    Q_INVOKABLE static void setDmabufFormatFilterForQt(bool enabled);

    Q_INVOKABLE KWin::KwinVirtualScreenParams createVirtScreenParams(const QString &name, const QString &description, const QSize &size, qreal scale)
    {
        return KWin::KwinVirtualScreenParams{name, description, size, scale};
    };

    /* Forces the mouse pointer to hover over the window */
    Q_INVOKABLE static void setHackedFocus(Window *window);

    Q_INVOKABLE void activateOutput(KWin::BackendOutput *window, qreal scale = 2);

    bool isScreenLocked() const;

    /* Surface related stuff */
    Q_INVOKABLE SurfaceInterface *winGetSurf(Window *window);
    Q_INVOKABLE int surfaceIndex(SurfaceInterface *surface);

    /* Window helpers */
    Q_INVOKABLE void windowOffscreenRef(Window *window, bool ref);
    Q_INVOKABLE bool windowIsInternal(Window *window);

    Q_INVOKABLE void windowMove(Window *window, const QPointF &topLeft);

    KWin::Window *forcedFocusWindow() const;
    void setForcedFocusWindow(KWin::Window *newForcedFocusWindow);

    /* keys */
    Q_INVOKABLE static bool keyMatch(int key, int modifiers, const QString &binding);
    Q_INVOKABLE static QString keyToString(int key, int modifiers);
    Q_INVOKABLE static QString normalizeKey(const QString &binding);

    /* Return position of an intersection of a ray emitted from the point in space to a point on the infinitie plane
     *
     * planeNormal and rayDirection should be normalized vectors
     *
     *          --- |
     *          --- |
     * X----------->| <- intersection
     *              |
     *              |
     */
    Q_INVOKABLE static IntersectionResult rayPlaneIntersection(const QVector3D &rayOrigin, const QVector3D &rayDirection,
                                                               const QVector3D &planeCenter, const QVector3D &planeNormal);

    /* Casts ray from source to an infinite plane with the center at the target position
     * returns coordinates and a distance of the ray-plane intersection
     */
    Q_INVOKABLE static IntersectionResult rayPlaneIntersection(const QQuick3DNode *source, const QQuick3DNode *target);

    /* Returns quaternion that can rotate 'source' to 'destination' */
    Q_INVOKABLE static QQuaternion getRotationDelta(const QQuaternion &source, const QQuaternion &destination);
    Q_INVOKABLE static QQuaternion getNodesSceneRotationDelta(const QQuick3DNode *source, const QQuick3DNode *destination);

    Q_INVOKABLE static QQuaternion multiplyQuaternions(const QQuaternion &a, const QQuaternion &b)
    {
        return a * b;
    }

    /* Returns rotation relative to node's parent from sceneRotation
     *
     * QQuaternion newSceneRotation = ...
     * auto localRotation = sceneRotationToNodeRotation(node, newSceneRotation)
     * node->setRotation(localRotation)
     *
     * then they will be equal:
     * node->sceneRotation() == newSceneRotation
     */
    Q_INVOKABLE static QQuaternion sceneRotationToNodeRotation(const QQuick3DNode *node, const QQuaternion &sceneRotation);

    /* Returns rotation relative to node's parent from target's sceneRotation
     *
     * auto localRotation = targetSceneRotationToNodeRotation(node, target)
     * node->setRotation(localRotation)
     *
     * then, rotations of both nodes will become the smae in the scene space:
     * node->sceneRotation() == target->sceneRotation()
     */
    Q_INVOKABLE static QQuaternion targetSceneRotationToNodeRotation(const QQuick3DNode *node, const QQuick3DNode *targetNode);

    /* Calculates and sets rotation of 'node' so its rotation in scene space becomes 'sceneRotation' */
    Q_INVOKABLE static void setNodeRotationFromScene(QQuick3DNode *node, const QQuaternion &sceneRotation);

    /* Calculates and sets position of 'node' so its position in scene space becomes 'scenePosition' */
    Q_INVOKABLE static void setNodePositionFromScene(QQuick3DNode *node, const QVector3D &scenePosition);

    /**
     * Rotates node so its front face (+Z) points toward the target.
     * Roll is copied from target's rotation.
     *
     * @param node The node to rotate
     * @param target The target to face; roll will match target's roll
     */
    Q_INVOKABLE static void turnToFace(QQuick3DNode *node, const QQuick3DNode *target);

    /**
     * Rotates node so its front face (+Z) points toward the target.
     * Roll is preserved from node's current rotation.
     *
     * @param node The node to rotate
     * @param target The target to face
     */
    Q_INVOKABLE static void turnToFaceKeepRoll(QQuick3DNode *node, const QQuick3DNode *target);

    /**
     * Computes a rotation quaternion that faces along the given forward direction,
     * using the reference rotation to derive the up vector for roll alignment.
     *
     * @param forward The direction to face (should be normalized)
     * @param referenceRotation Rotation used to derive up vector and handle edge cases
     * @return Quaternion representing the computed rotation
     */
    Q_INVOKABLE static QQuaternion rotationToFaceDirection(const QVector3D &forward,
                                                           const QQuaternion &referenceRotation);

    Q_INVOKABLE static QVector3D rotateVector(const QQuaternion &rotation, const QVector3D &vector);

    /**
     * Computes ray-sphere intersections.
     *
     * @param rayOrigin Starting point of the ray
     * @param rayDirection Direction of the ray (should be normalized)
     * @param sphereCenter Center of the sphere
     * @param sphereRadius Radius of the sphere
     * @return (t1, t2) where each is an intersection at rayOrigin + t * rayDirection,
     *         or (-1, -1) if no intersection exists.
     */
    /**
     * Extracts pitch and yaw angles (in degrees) of 'current' relative to 'initial'.
     * Returns QVector2D(pitch_deg, yaw_deg) where:
     *   pitch > 0 = look up,  yaw > 0 = look right
     */
    Q_INVOKABLE static QVector2D headAnglesFromInitialRotation(const QQuaternion &initial,
                                                               const QQuaternion &current);

    Q_INVOKABLE static QVector2D raySphereIntersect(const QVector3D &rayOrigin,
                                                    const QVector3D &rayDirection,
                                                    const QVector3D &sphereCenter,
                                                    float sphereRadius);
    /**
     * Returns the farthest positive intersection t from raySphereIntersect().
     *
     * @return The largest positive t, or -1 if both intersections are behind the origin.
     */
    Q_INVOKABLE static float raySphereIntersectFar(const QVector3D &rayOrigin,
                                                   const QVector3D &rayDirection,
                                                   const QVector3D &sphereCenter,
                                                   float sphereRadius);

    /**
     * Computes a quaternion that rotates vector 'from' to vector 'to'.
     * Both vectors are normalized internally.
     *
     * @param from The source direction vector
     * @param to The target direction vector
     * @return Quaternion that rotates 'from' to 'to'
     */
    Q_INVOKABLE static QQuaternion rotationBetweenVectors(const QVector3D &from, const QVector3D &to);

    /**
     * Computes a quaternion that rotates vector 'from' to vector 'to', while keeping
     * roll aligned to the given reference rotation.
     *
     * @param from The source direction vector
     * @param to The target direction vector
     * @param referenceRotation Rotation used to preserve roll alignment
     * @return Quaternion that rotates 'from' to 'to' with preserved roll
     */
    Q_INVOKABLE static QQuaternion rotationBetweenVectorsKeepRoll(const QVector3D &from,
                                                                  const QVector3D &to,
                                                                  const QQuaternion &referenceRotation);

    /**
     * Computes a quaternion that rotates vector 'from' to vector 'to', preserving
     * the existing roll of currentRotation relative to referenceRotation.
     *
     * Algorithm:
     * 1. Compute base rotation using cross-product (rotates from -> to)
     * 2. Measure roll before and after applying base rotation
     * 3. Apply correction rotation around 'to' to restore original roll
     *
     * @param from The source direction vector (must be normalized)
     * @param to The target direction vector (must be normalized)
     * @param currentRotation The rotation this result will be applied to
     * @param referenceRotation The reference for roll measurement (e.g., camera rotation)
     * @return Quaternion that rotates 'from' to 'to' preserving existing roll
     */
    Q_INVOKABLE static QQuaternion rotationBetweenVectorsPreserveRoll(const QVector3D &from,
                                                                      const QVector3D &to,
                                                                      const QQuaternion &currentRotation,
                                                                      const QQuaternion &referenceRotation);

    /**
     * Computes roll angle difference (in degrees) between a reference rotation and a current up vector
     * around a given forward direction. Returns 0 when aligned.
     *
     * @param referenceRotation Rotation used to derive reference up
     * @param forwardDirection Forward direction defining the roll axis
     * @param currentUp Current up direction to compare
     * @return Roll angle in degrees
     */
    Q_INVOKABLE static float rollAngleBetween(const QQuaternion &referenceRotation,
                                              const QVector3D &forwardDirection,
                                              const QVector3D &currentUp);

    /**
     * Computes roll angle (degrees) between a reference up and current up around a forward direction.
     *
     * @param referenceUp World up direction to preserve
     * @param forwardDirection Forward direction defining roll axis
     * @param currentUp Current up direction to compare
     * @return Roll angle in degrees
     */
    Q_INVOKABLE static float rollAngleBetweenUp(const QVector3D &referenceUp,
                                                const QVector3D &forwardDirection,
                                                const QVector3D &currentUp);

    /* Uses currentRotation to derive forward and up for roll comparison. */
    Q_INVOKABLE static float rollAngleBetween(const QQuaternion &referenceRotation,
                                              const QQuaternion &currentRotation);

    /* Uses currentRotation for up and explicit forwardDirection for roll axis. */
    Q_INVOKABLE static float rollAngleBetween(const QQuaternion &referenceRotation,
                                              const QQuaternion &currentRotation,
                                              const QVector3D &forwardDirection);

    /**
     * Rotates a relative pose by a given rotation (both rotation and position are rotated).
     *
     * @param pose Pose expressed in a node's local space
     * @param rotation Rotation to apply
     * @return Rotated pose in the same local space
     */
    Q_INVOKABLE static RelativePose rotateRelativePose(const RelativePose &pose,
                                                       const QQuaternion &rotation);

    /**
     * Captures target's scene position and scene rotation and converts them to be relative to node.
     * Rotation is stored as a scene-space delta; position is stored in node's local space.
     *
     * @param node Reference node used as the local space
     * @param target Target node whose relative pose is captured
     * @return RelativePose describing target relative to node
     */
    Q_INVOKABLE static RelativePose getRelativePose(QQuick3DNode *node, const QQuick3DNode *target);

    /**
     * Applies a stored relative pose so target keeps the same offset to node.
     * Position is treated as node-local; rotation is applied in scene space.
     *
     * @param node Reference node used as the local space
     * @param target Target node to update
     * @param pose RelativePose previously captured for node
     */
    Q_INVOKABLE static void applyRelativePose(const QQuick3DNode *node, QQuick3DNode *target, const RelativePose &pose);

    /**
     * Converts a pose relative to node into a scene-space pose.
     * Useful when you need explicit scene rotation and scene position.
     *
     * @param node Node that defines the local space
     * @param pose Pose expressed relative to node
     * @return Pose expressed in scene space
     */
    Q_INVOKABLE static RelativePose relativePoseToScenePose(const QQuick3DNode *node, const RelativePose &pose);

    /**
     * Converts a pose relative to currentNode into a pose relative to newNode.
     *
     * @param currentNode Node that pose is currently relative to
     * @param newNode Node that the returned pose will be relative to
     * @param pose Pose expressed relative to currentNode
     * @return Pose expressed relative to newNode
     */
    Q_INVOKABLE static RelativePose relativePoseToRelativePose(const QQuick3DNode *currentNode,
                                                               const QQuick3DNode *newNode,
                                                               const RelativePose &pose);

    /**
     * Converts a rotation relative to currentNode into a rotation relative to newNode.
     *
     * @param currentNode Node that rotation is currently relative to
     * @param newNode Node that the returned rotation will be relative to
     * @param rotation Rotation expressed relative to currentNode
     * @return Rotation expressed relative to newNode
     */
    Q_INVOKABLE static QQuaternion relativeRotationToRelativeRotation(const QQuick3DNode *currentNode,
                                                                      const QQuick3DNode *newNode,
                                                                      const QQuaternion &rotation);

    /* VR pose persistence */
    Q_INVOKABLE static void saveVrPose(QObject *window, const QVector3D &position,
                                        const QQuaternion &rotation, float curvature);
    Q_INVOKABLE static bool hasVrPose(QObject *window);
    Q_INVOKABLE static QVector3D vrPosePosition(QObject *window);
    Q_INVOKABLE static QQuaternion vrPoseRotation(QObject *window);
    Q_INVOKABLE static float vrPoseCurvature(QObject *window);

Q_SIGNALS:
    void screenLockedChanged();
    void forcedFocusWindowChanged();
};

}
