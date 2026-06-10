/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

import "WindowSnapLogic.js" as SnapLogic

Node {
    id: root
    visible: !root.client.minimized && root.client.opacity > 0 && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    required property KwinWindowModel windowDataModel
    required property Component nextComponent
    required property QtObject client
    required property VrFocusControl focusControl

    property real ppu: 20
    property Node grabHandle
    property real normalWindowFlexibleBottom: 0
    property real zOffsetGlobal: 0

    // Snapshot of pre-snap frame size, captured by WindowSnapManager on first
    // snap. Restored on detach. Null = window has never been snapped.
    property var preSnapGeom: null

    // Stack tracking — set by WindowSnapManager when this window is stacked
    // onto another. stackedOnto = target window. stackIndex = position in
    // cascade (1 = first child, 2 = second, etc.).
    property var stackedOnto: null
    property int stackIndex: 0

    // A stack is one rigid container: members match the root's full frame
    // size (VOC-SNAP-060) and KEEP matching it (#18) — otherwise any later
    // client resize drifts the layout apart. Watch both the root's geometry
    // (propagate down) and our own (a member resizing itself snaps back).
    // Converges: once sizes match the delta is zero and nothing is issued.
    // Cascade offsets are size-independent, so no reposition is needed.
    function _matchStackRootSize() {
        if (!stackedOnto || !stackedOnto.client || !client)
            return
        const rg = stackedOnto.client.frameGeometry
        const mg = client.frameGeometry
        const dw = rg.width - mg.width
        const dh = rg.height - mg.height
        if (Math.abs(dw) > 0.5 || Math.abs(dh) > 0.5)
            KwinVrHelpers.windowResize(client, dw, dh)
    }
    Connections {
        // ?? null: undefined would not coerce to QObject*
        target: (root.stackedOnto ? root.stackedOnto.client : null) ?? null
        function onFrameGeometryChanged() { root._matchStackRootSize() }
    }
    Connections {
        target: root.client
        enabled: root.stackedOnto !== null
        function onFrameGeometryChanged() { root._matchStackRootSize() }
    }

    // Same container rigidity for POSE (#18): if the root's node moves
    // outside a drag (e.g. the space allocator re-places it after a resize),
    // members must keep their cascade offset relative to it. During a root
    // drag members are reparented under the root (VOC-SNAP-080) — transform
    // inheritance already carries them, so skip while we're its child.
    // Converges: a no-op write doesn't re-emit scenePositionChanged.
    function _followStackRootPose() {
        if (!stackedOnto || parent === stackedOnto)
            return
        const r = SnapLogic.landingPose(0, 0, 0, 0, KWinVRConfig.zSurfaceMarginTop,
                                        SnapLogic.ActionStack, Math.max(stackIndex, 1))
        KwinVrHelpers.setNodePositionFromScene(
            root, stackedOnto.mapPositionToScene(Qt.vector3d(r.x, r.y, r.z)))
        KwinVrHelpers.setNodeRotationFromScene(root, stackedOnto.sceneRotation)
    }
    Connections {
        target: root.stackedOnto ?? null
        function onScenePositionChanged() { root._followStackRootPose() }
        function onSceneRotationChanged() { root._followStackRootPose() }
    }

    // Emitted when this window becomes active and is part of a stack — so
    // WindowSnapManager can promote it to top of cascade.
    signal stackFocusRequested()

    Connections {
        target: root.client
        function onMoveResizedChanged() {
            if(root.client.resize || root.client.move) {
                root.focusControl.currentMovingResizingWindow = windowLoader.item
            } else if(root.focusControl.currentMovingResizingWindow === windowLoader.item) {
                root.focusControl.currentMovingResizingWindow = null
            }
        }
    }

    Component {
        id: decoratedSurfaceComponent
        KwinDecoratedSurfacedWindow3D {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Component {
        id: thumbnailComponent
        KwinWindowThumbnail3D {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Component {
        id: thumbnailXrItemComponent
        KwinWindowThumbnailXrItem {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    //  1. Draw the main window using Loader3D based on configuration
    Loader3D {
        id: windowLoader
        sourceComponent: {
            switch(KWinVRConfig.windowMode) {
                case 0: return decoratedSurfaceComponent; // DecoratedSurface
                case 1: return thumbnailComponent; // Thumbnail
                case 2: return thumbnailXrItemComponent; // ThumbnailXrItem
                default: return decoratedSurfaceComponent;
            }
        }
    }

    //  2. Draw the stack of transient menus always above the main window
    // (currently not only menus, but all non top-level windows)
    Repeater3D {
        id: menuRepeater
        model: TransientMenusWindowFilter {
            forTransient: root.client
            windowModel: root.client?.managed ? root.windowDataModel : null
        }
        delegate: root.nextComponent
    }

    ZStacker {
        id: menuStack
        target: menuRepeater
        initialMargins: windowLoader.item?.itemDepth ?? ({top: 0, bottom: 0})
        childIndexPropertyName: "stackingOrder"
        globalOffset: root.zOffsetGlobal
    }

    //  3. Draw the stack of normal transient windows always above menu stack
    Repeater3D {
        id: transientNormalsRepeater
        model: TransientNormalWindowFilter {
            forTransient: root.client
            windowModel: root.client?.managed ? root.windowDataModel : null
        }
        delegate: root.nextComponent
    }
    ZStacker {
        id: transientNormalsStack
        target: transientNormalsRepeater
        initialMargins: menuStack.depth
        childIndexPropertyName: "stackingOrder"
        globalOffset: root.zOffsetGlobal
    }

    // 4. Get total depth: If the main window was a normal window then add flexible bottom
    property zMargins itemDepth:  ({
                                       top: transientNormalsStack.depth.top,
                                       bottom: transientNormalsStack.depth.bottom,
                                       flexibleTop: 0,
                                       flexibleBottom: (root.client.normalWindow && root.visible) ? root.normalWindowFlexibleBottom : 0,
                                   })
}
