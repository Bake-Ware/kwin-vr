/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QQuaternion>
#include <QTimer>
#include <QtQuick3D/private/qquick3dnode_p.h>

namespace KWin
{

/**
 * Rotates and moves the rotationTarget if no tracked objects are inside FOV
 * to bring the closest tracked object into the center of the camera's view.
 * Stops when stopFOV is reached.
 *
 * NOTE: Tracked objects should be children of the rotationTarget or this will break.
 */
class VrFollowMode : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QQuick3DNode *camera READ camera WRITE setCamera NOTIFY cameraChanged FINAL)
    Q_PROPERTY(QQuick3DNode *rotationTarget READ rotationTarget WRITE setRotationTarget NOTIFY rotationTargetChanged FINAL)
    Q_PROPERTY(int fovH READ fovH WRITE setFovH NOTIFY fovHChanged FINAL)
    Q_PROPERTY(int fovV READ fovV WRITE setFovV NOTIFY fovVChanged FINAL)
    Q_PROPERTY(int stopFovH READ stopFovH WRITE setStopFovH NOTIFY stopFovHChanged FINAL)
    Q_PROPERTY(int stopFovV READ stopFovV WRITE setStopFovV NOTIFY stopFovVChanged FINAL)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged FINAL)
    Q_PROPERTY(double delay READ delay WRITE setDelay NOTIFY delayChanged FINAL)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged FINAL)
    Q_PROPERTY(bool worldUpAlignment READ worldUpAlignment WRITE setWorldUpAlignment NOTIFY worldUpAlignmentChanged FINAL)

    QML_ELEMENT
public:
    explicit VrFollowMode(QObject *parent = nullptr);

    QQuick3DNode *camera() const;
    void setCamera(QQuick3DNode *camera);

    QQuick3DNode *rotationTarget() const;
    void setRotationTarget(QQuick3DNode *rotationTarget);

    bool worldUpAlignment() const;
    void setWorldUpAlignment(bool worldUpAlignment);

    int fovH() const;
    void setFovH(int fovH);

    int fovV() const;
    void setFovV(int fovV);

    int stopFovH() const;
    void setStopFovH(int stopFovH);

    int stopFovV() const;
    void setStopFovV(int stopFovV);

    bool active() const;

    double delay() const;
    void setDelay(double delay);

    double speed() const;
    void setSpeed(double speed);

    Q_INVOKABLE void registerObject(QQuick3DNode *node);
    Q_INVOKABLE void unregisterObject(QQuick3DNode *node);

    // Force-pan to center `node`. Takes an explicit camera (the normal
    // `camera` binding gets null'd during hover/grab/menu, which would
    // otherwise suppress the pan). The override stays locked on `node`
    // until stop-FOV is reached, `node` is destroyed, or unfocus(node).
    Q_INVOKABLE void focusOn(QQuick3DNode *node, QQuick3DNode *camera);

    // Cancel an in-flight focusOn pan for `node`. No-op when `node` is not
    // the current focus target. Needed when the caller moves the node away
    // mid-pan (e.g. pose restore on defocus) — otherwise the override keeps
    // dragging the world after it.
    Q_INVOKABLE void unfocus(QQuick3DNode *node);

Q_SIGNALS:
    void cameraChanged();
    void rotationTargetChanged();
    void fovHChanged();
    void fovVChanged();
    void delayChanged();
    void speedChanged();
    void worldUpAlignmentChanged();
    void stopFovHChanged();
    void stopFovVChanged();
    void activeChanged();

private:
    void onFrame();
    void updateConnections();
    // The camera FOV/pan math should use right now: the explicit focusOn
    // camera while an override is active, the normal binding otherwise.
    QQuick3DNode *effectiveCamera() const;
    void clearFocusOverride();
    QVector2D anglesToNode(const QQuick3DNode *node) const;
    bool anyNodeInFov() const;
    QQuick3DNode *findClosestNode() const;
    bool isNodeInStopFov(const QQuick3DNode *node) const;
    void setActive(bool active);
    void rotateTowardsNode(QQuick3DNode *node, double dt);

    QQuick3DNode *m_camera = nullptr;
    QQuick3DNode *m_rotationTarget = nullptr;
    QList<QQuick3DNode *> m_trackedNodes;
    // When set, onFrame pans toward this node instead of the angularly-closest
    // tracked node. Cleared once the node reaches the stop-FOV.
    QQuick3DNode *m_focusOverride = nullptr;
    // Camera used while an override is active. Separate from m_camera so
    // focus-pan works even when the main `camera` binding is gated null
    // during hover/grab/menu interactions.
    QQuick3DNode *m_focusCamera = nullptr;
    QMetaObject::Connection m_focusNodeDestroyed;
    QMetaObject::Connection m_focusCameraDestroyed;
    bool m_worldUpAlignment = true;

    int m_fovH = 50;
    int m_fovV = 45;
    int m_stopFovH = 5;
    int m_stopFovV = 5;
    double m_delay = 0.5;
    double m_speed = 3.0;

    bool m_active = false;
    double m_lookAwayTime = 0.0;
    QElapsedTimer m_timer;
    QTimer m_frameTimer;
};

} // namespace KWin
