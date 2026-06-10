/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "../vrfollowmode.h"

#include <QSignalSpy>
#include <QTest>
#include <QtMath>
#include <QtQuick3D/private/qquick3dnode_p.h>

using namespace KWin;

// Focus-pull pan (#26 follow-up, VOC-FOCUS-020): focusOn must run the frame
// loop with its explicit camera even while the normal `camera` binding is
// null (the QML scene null-gates it during hover/grab/menu), pan the
// rotation target until the node reaches the stop-FOV, then clear itself.
class TestVrFollowMode : public QObject
{
    Q_OBJECT

    // Angle (degrees) between camera forward (-Z) and the direction to the
    // node, in the horizontal plane — the same quantity the FOV checks use.
    static float hAngleTo(const QQuick3DNode *camera, const QQuick3DNode *node)
    {
        const QVector3D toNode = node->scenePosition() - camera->scenePosition();
        const QVector3D localDir = camera->mapDirectionFromScene(toNode).normalized();
        return qAbs(qRadiansToDegrees(qAtan2(localDir.x(), -localDir.z())));
    }

private Q_SLOTS:
    void focusOnPansNodeIntoStopFov()
    {
        QQuick3DNode scene;
        QQuick3DNode camera;
        camera.setParent(&scene);
        camera.setParentItem(&scene); // origin, facing -Z

        QQuick3DNode handle;
        handle.setParent(&scene);
        handle.setParentItem(&scene);
        handle.setPosition(QVector3D(0, 0, -150));

        QQuick3DNode window;
        window.setParent(&handle);
        window.setParentItem(&handle);
        // Scene position (50, 0, 150): behind the viewer, well outside FOV.
        window.setPosition(QVector3D(50, 0, 300));

        VrFollowMode follow;
        follow.setRotationTarget(&handle);
        follow.registerObject(&window);
        // The normal camera binding stays null — exactly the hover/grab/menu
        // gating focusOn exists to bypass.
        QVERIFY(!follow.camera());
        QVERIFY(qAbs(hAngleTo(&camera, &window)) > follow.fovH());

        follow.focusOn(&window, &camera);
        QVERIFY(follow.active());

        // The 16ms frame loop pans the handle around the camera pivot until
        // the window reaches the stop-FOV, then deactivates.
        QTRY_VERIFY_WITH_TIMEOUT(!follow.active(), 15000);
        QVERIFY(hAngleTo(&camera, &window) <= follow.stopFovH() + 1.0f);
        // In front of the viewer, not behind.
        QVERIFY(window.scenePosition().z() < 0.0f);
    }

    void focusOnNoOpsWhenAlreadyInFov()
    {
        QQuick3DNode scene;
        QQuick3DNode camera;
        camera.setParent(&scene);
        camera.setParentItem(&scene);

        QQuick3DNode handle;
        handle.setParent(&scene);
        handle.setParentItem(&scene);

        QQuick3DNode window;
        window.setParent(&handle);
        window.setParentItem(&handle);
        window.setPosition(QVector3D(0, 0, -150)); // dead ahead

        VrFollowMode follow;
        follow.setRotationTarget(&handle);
        follow.registerObject(&window);

        const QVector3D before = window.scenePosition();
        follow.focusOn(&window, &camera);
        QVERIFY(!follow.active());
        QTest::qWait(100);
        QCOMPARE(window.scenePosition(), before);
    }

    void destroyedTargetStopsThePan()
    {
        QQuick3DNode scene;
        QQuick3DNode camera;
        camera.setParent(&scene);
        camera.setParentItem(&scene);

        QQuick3DNode handle;
        handle.setParent(&scene);
        handle.setParentItem(&scene);
        handle.setPosition(QVector3D(0, 0, -150));

        auto *window = new QQuick3DNode;
        window->setParent(&handle);
        window->setParentItem(&handle);
        window->setPosition(QVector3D(50, 0, 300));

        VrFollowMode follow;
        follow.setRotationTarget(&handle);
        follow.registerObject(window);
        follow.focusOn(window, &camera);
        QVERIFY(follow.active());

        delete window; // mid-pan
        // Override clears; with the normal camera binding still null the
        // frame loop must shut down instead of spinning on a dead target.
        QTRY_VERIFY(!follow.active());
    }

    void unfocusCancelsThePan()
    {
        QQuick3DNode scene;
        QQuick3DNode camera;
        camera.setParent(&scene);
        camera.setParentItem(&scene);

        QQuick3DNode handle;
        handle.setParent(&scene);
        handle.setParentItem(&scene);
        handle.setPosition(QVector3D(0, 0, -150));

        QQuick3DNode window;
        window.setParent(&handle);
        window.setParentItem(&handle);
        window.setPosition(QVector3D(50, 0, 300));

        QQuick3DNode other;
        other.setParent(&handle);
        other.setParentItem(&handle);

        VrFollowMode follow;
        follow.setRotationTarget(&handle);
        follow.registerObject(&window);
        follow.focusOn(&window, &camera);
        QVERIFY(follow.active());

        // Wrong node: the pan keeps going.
        follow.unfocus(&other);
        QVERIFY(follow.active());

        // Right node: the pan cancels — this is what the QML pose restore
        // relies on, or the override would drag the world after the
        // restored window.
        follow.unfocus(&window);
        QTRY_VERIFY(!follow.active());
        const QVector3D frozen = window.scenePosition();
        QTest::qWait(100);
        QCOMPARE(window.scenePosition(), frozen);
    }

    void unregisterClearsTheOverride()
    {
        QQuick3DNode scene;
        QQuick3DNode camera;
        camera.setParent(&scene);
        camera.setParentItem(&scene);

        QQuick3DNode handle;
        handle.setParent(&scene);
        handle.setParentItem(&scene);
        handle.setPosition(QVector3D(0, 0, -150));

        QQuick3DNode window;
        window.setParent(&handle);
        window.setParentItem(&handle);
        window.setPosition(QVector3D(50, 0, 300));

        VrFollowMode follow;
        follow.setRotationTarget(&handle);
        follow.registerObject(&window);
        follow.focusOn(&window, &camera);
        QVERIFY(follow.active());

        follow.unregisterObject(&window);
        QVERIFY(!follow.active());

        // The pan must actually have stopped: pose frozen from here on.
        const QVector3D frozen = window.scenePosition();
        QTest::qWait(100);
        QCOMPARE(window.scenePosition(), frozen);
    }
};

QTEST_GUILESS_MAIN(TestVrFollowMode)
#include "testvrfollowmode.moc"
