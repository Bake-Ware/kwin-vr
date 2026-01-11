/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    required property KwinVrInputDevice kwinInput
    required property VrHeadScroll headScroll
    required property Xray xray
    required property VrPicking picking
    required property VrHoverState hoverState

    // Set externally when a window starts moving/resizing
    property Node currentMovingResizingWindow: null

    // Optional constraint for pointer position filtering
    property VrPointerConstraint constraint: null

    // == Ray-plane Intersection ==

    property intersectionResult lastIntersection
    function updateLastIntersection(): void {
        if (root.currentMovingResizingWindow) {
            root.lastIntersection = KwinVrHelpers.rayPlaneIntersection(root.xray, root.currentMovingResizingWindow)
        }
    }

    function needRayPlaneIntersection(): bool {
        return !!root.currentMovingResizingWindow?.client
    }

    readonly property Connections intersectionUpdater: Connections {
        target: root.xray
        enabled: root.needRayPlaneIntersection()
        function onSceneTransformChanged(): void {
            root.updateLastIntersection()
        }
    }

    // == Pointer movement ==

    readonly property StateGroup pointerModeState: StateGroup {
        states: [
            State {
                name: "movingResizing"
                when: !!root.currentMovingResizingWindow?.client &&
                      !root.headScroll.headScrollActive &&
                      !root.xray.grabbedObject
                StateChangeScript {
                    script: Qt.callLater(root.picking.updateAllPicks)
                }
            },
            State {
                name: "picking"
                when:
                    root.hoverState.activePickHandler &&
                    !root.headScroll.headScrollActive &&
                    !root.xray.grabbedObject
                StateChangeScript {
                    script: Qt.callLater(root.updateLastIntersection)
                }
            }
        ]
    }

    function computePointerPositionFromIntersection(): point {
        if (!root.lastIntersection.valid) {
            return kwinInput.pointerPosition
        }

        const target = root.currentMovingResizingWindow
        const geom = target.client.frameGeometry
        const localPos = target.mapPositionFromScene(root.lastIntersection.position)
        const ppu = target.ppu
        return Qt.point(
            geom.x + geom.width/2 + localPos.x * ppu,
            geom.y + geom.height/2 - localPos.y * ppu
        )
    }

    readonly property bool constraintActive: root.constraint !== null && root.constraint.enabled

    property Connections pointerPositionUpdaterDirect: Connections {
        target: root
        enabled: root.pointerModeState.state === "movingResizing" && !root.constraintActive
        function onLastIntersectionChanged(): void {
            root.kwinInput.pointerPosition = root.computePointerPositionFromIntersection()
        }
    }

    property Connections pointerPositionUpdaterFiltered: Connections {
        target: root
        enabled: root.pointerModeState.state === "movingResizing" && root.constraintActive
        function onLastIntersectionChanged(): void {
            root.kwinInput.pointerPosition = root.constraint.filter(root.computePointerPositionFromIntersection())
        }
    }

    function computePointerPositionFromPick(): point {
        const handler = root.hoverState.activePickHandler
        if (!handler)
            return kwinInput.pointerPosition

        const coords = handler.target.uvToWindow2DCoordinates(root.picking.lastPick.uvPosition)
        const geom = handler.geometry
        return Qt.point(geom.x + coords.x, geom.y + coords.y)
    }

    property Connections pointerPositionUpdaterPicking: Connections {
        target: root.picking
        enabled: root.pointerModeState.state === "picking"
        function onLastPickChanged(): void {
            root.kwinInput.pointerPosition = root.computePointerPositionFromPick()
        }
    }

    // Special handler for VRWindow: a 3d object that contains 2D GUI
    readonly property VRWindow currentHoveredVRWindow: root.picking.hoveredObject as VRWindow
    readonly property QtObject kwinToQQuickBridge: KWinToQQuick3DInputBridge {
        id: bridge3d
        target: root.currentHoveredVRWindow ? root.picking.hoveredItem : null
    }

    readonly property Binding rayInputVRWindowBinding: Binding {
        bridge3d.pointerPosition: Qt.point(root.picking.lastPick.uvPosition.x, root.picking.lastPick.uvPosition.y)
        when: root.currentHoveredVRWindow && !root.currentMovingResizingWindow && !root.xray.grabbedObject
    }

    // Active client for KWin focus: this way we tell kwin that all pointer events should be delivered to this window
    readonly property var activeClient: currentMovingResizingWindow?.client ?? hoverState.activePickHandler?.client ?? null

    // Explicit target/property/value form required because KwinVrHelpers is a singleton.
    // The shorthand "Singleton.prop: value" syntax is parsed as an attached property.
    readonly property Binding forcedFocusBinding: Binding {
        target: KwinVrHelpers
        property: "forcedFocusWindow"
        value: root.activeClient
    }
}
