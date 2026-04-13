/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    required property Xray xray
    required property Node cursor3d
    required property VrPicking picking
    required property VrPointerHandler pointerHandler
    required property Node currentMovingResizingWindow
    property bool cursorEnabled: true

    // This is still used as an indicator that we hover something in XrScene
    readonly property Node cursorHoverObject: root.currentMovingResizingWindow ?? root.picking.hoveredObject

    // TODO: need to convert this to StateGroup instead of these two bindings
    readonly property Binding movingResizingCursorRotation: Binding {
        target: root.cursor3d
        property: "rotation"
        value: root.currentMovingResizingWindow?.sceneRotation ?? Qt.quaternion(1,0,0,0)
        when: root.currentMovingResizingWindow
    }
    readonly property Binding movingResizingCursorPosition: Binding {
        target: root.cursor3d
        property: "position"
        value: {
            if(!root.pointerHandler.lastIntersection.valid || !root.currentMovingResizingWindow) {
                return Qt.vector3d(0,0,0)
            } else {
                const normal = root.currentMovingResizingWindow.mapDirectionToScene(Qt.vector3d(0,0,1))
                return root.cursor3d.calcHoveredPosition(root.pointerHandler.lastIntersection.position, normal)
            }
        }
        when: root.currentMovingResizingWindow
    }
    readonly property Binding movingResizingCursorVisible: Binding {
        target: root.cursor3d
        property: "visible"
        value: root.cursorEnabled && root.pointerHandler.lastIntersection.valid && !!root.currentMovingResizingWindow
        when: root.currentMovingResizingWindow
    }

    readonly property Binding hoveringCursorRotation: Binding {
        target: root.cursor3d
        property: "rotation"
        value: root.picking.hoveredObject?.sceneRotation ?? Qt.quaternion(1,0,0,0)
        when: root.picking.hoveredObject && !root.currentMovingResizingWindow && root.xray.enabled
    }
    readonly property Binding hoveringCursorPosition: Binding {
        target: root.cursor3d
        property: "position"
        value: root.cursor3d.calcHoveredPosition(root.picking.lastPick.scenePosition, root.picking.lastPick.sceneNormal)
        when: root.picking.hoveredObject && !root.currentMovingResizingWindow && root.xray.enabled
    }
    readonly property Binding hoveringCursorVisible: Binding {
        target: root.cursor3d
        property: "visible"
        value: root.cursorEnabled && !!root.picking.hoveredObject
        when: root.picking.hoveredObject && !root.currentMovingResizingWindow && root.xray.enabled
    }
}
