/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * Vr2DViewport — fullscreen Plasma client window that renders the
 * curved-plane scene with a 2D camera + mouse input.
 *
 * Input model (single MouseArea owns the gesture, no
 * OrbitCameraController — they fought over event grab and trunctated
 * drags):
 *   - LMB on plane → grab + drag at constant pick depth.
 *   - LMB / MMB / RMB on empty → orbit (custom math around orbitOrigin).
 *   - Wheel: alt = curvature on hovered plane; plain = dolly-zoom.
 *   - Esc / Window close → KwinVrBridge.requestVrDeactivate().
 */

import QtQuick
import QtQuick.Window
import QtQuick3D

import org.kde.kwin.vr

Window {
    id: root

    title: qsTr("KWin-VR Viewport")
    color: "skyblue"
    width: Screen.width > 1 ? Screen.width : 1280
    height: Screen.height > 1 ? Screen.height : 720
    visible: true
    visibility: Window.FullScreen

    onClosing: KwinVrBridge.requestVrDeactivate()

    Item {
        id: keyHost
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: KwinVrBridge.requestVrDeactivate()
    }

    // === Camera state (orbit around origin) ===
    property real _yawDeg: 0
    property real _pitchDeg: 0
    property real _radius: 0
    property real _orbitSensitivity: 0.4
    property real _zoomSensitivity: 0.1

    function _updateCamera() {
        const yaw = _yawDeg * Math.PI / 180
        const pitch = _pitchDeg * Math.PI / 180
        const ox = orbitOrigin.position.x
        const oy = orbitOrigin.position.y
        const oz = orbitOrigin.position.z
        orbitCam.position = Qt.vector3d(
            ox + _radius * Math.cos(pitch) * Math.sin(yaw),
            oy + _radius * Math.sin(pitch),
            oz + _radius * Math.cos(pitch) * Math.cos(yaw)
        )
        orbitCam.eulerRotation = Qt.vector3d(-_pitchDeg, _yawDeg, 0)
    }

    Component.onCompleted: {
        _radius = scene.distance
        _updateCamera()
    }

    View3D {
        id: view3d
        anchors.fill: parent
        camera: orbitCam

        environment: SceneEnvironment {
            clearColor: "skyblue"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        WindowSceneRoot {
            id: scene
            viewpoint: orbitCam
        }

        Node {
            id: orbitOrigin
            position: Qt.vector3d(0, 0, -scene.distance)
        }

        PerspectiveCamera {
            id: orbitCam
            fieldOfView: 60
            clipNear: 0.1
            clipFar: 1000

            // Head-locked HUD overlays.
            Node {
                id: hudNode

                readonly property int dw: KWinVRConfig.width * KWinVRConfig.scale
                readonly property int dh: KWinVRConfig.height * KWinVRConfig.scale
                readonly property real surfaceW: dw / scene.ppu * KWinVRConfig.hudScaleH
                readonly property real surfaceH: dh / scene.ppu * KWinVRConfig.hudScaleV
                readonly property real hudDistance: scene.distance * KWinVRConfig.hudDistanceFraction / 100.0
                readonly property real hudY: -(hudDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))

                position: Qt.vector3d(0, hudY, -hudDistance)

                Loader3D {
                    active: KWinVRConfig.hudEnabled || KWinVRConfig.debugDisplayEnabled
                    sourceComponent: VrHudPlane {
                        ppu: scene.ppu
                        displayWidth: hudNode.dw
                        displayHeight: hudNode.dh
                    }
                }

                Repeater3D {
                    model: HudWindowFilter {
                        windowModel: scene.windowDataModel
                        showNotifications: KWinVRConfig.hudShowNotifications
                        showOsd: KWinVRConfig.hudShowOsd
                        showDock: KWinVRConfig.hudShowDock
                        showAppletPopup: KWinVRConfig.hudShowAppletPopup
                    }
                    delegate: VrHudWindow {
                        required property QtObject window
                        client: window
                        ppu: scene.ppu
                        hudSurfaceW: hudNode.surfaceW
                        hudSurfaceH: hudNode.surfaceH
                        hudCurvature: KWinVRConfig.hudCurvature
                    }
                }
            }
        }

        DirectionalLight {
            eulerRotation.x: -30
            eulerRotation.y: -45
        }
    }

    // === Plane interaction helpers ===
    property var _hoveredPlane: null

    function _refreshHoveredPlane(x, y) {
        const result = view3d.pick(x, y)
        if (!result.objectHit) { _hoveredPlane = null; return }
        const p = scene.planeInteraction.planeFromObject(result.objectHit)
        _hoveredPlane = (p && !p._isPseudomirror) ? p : null
    }

    function curvatureNudge(direction) {
        const plane = _hoveredPlane
        if (!plane) return
        const step = (KWinVRConfig.curvatureScrollStep || 0.1) * direction
        const ab = plane.abductor
        if (ab) {
            const cur = plane.effectiveCurvature
            const next = Math.max(0, Math.min(6, cur + step))
            ab.updateSlotOverrides(plane.planeId, { curvature: next })
        } else {
            plane.intrinsicCurvature = Math.max(0, Math.min(6,
                plane.intrinsicCurvature + step))
        }
        // Curvature sync across viewports deferred — it conflicts with
        // the drag-driven isGrabbed toggling because it's a one-shot
        // change without a matching grab-end signal. Most users live
        // with per-viewport curvature for now.
    }

    function resetView() {
        _yawDeg = 0
        _pitchDeg = 0
        _radius = scene.distance
        orbitOrigin.position = Qt.vector3d(0, 0, -scene.distance)
        _updateCamera()
    }

    // === Unified input ===
    // No OrbitCameraController — it fought with the grab MouseArea over
    // event grab and truncated drags. Custom orbit math here.
    MouseArea {
        id: gesture
        anchors.fill: view3d
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true

        // "" | "grab" | "orbit"
        property string mode: ""
        property real lastX: 0
        property real lastY: 0
        property real grabDepth: 0
        property vector3d grabOffset: Qt.vector3d(0, 0, 0)

        onPositionChanged: (mouse) => {
            const dx = mouse.x - lastX
            const dy = mouse.y - lastY
            lastX = mouse.x; lastY = mouse.y

            if (mode === "grab") {
                const plane = scene.planeInteraction._grabbedPlane
                if (!plane) return
                const mouseScene = view3d.mapTo3DScene(
                    Qt.vector3d(mouse.x, mouse.y, grabDepth))
                const newPos = mouseScene.plus(grabOffset)
                KwinVrHelpers.setNodePositionFromScene(plane, newPos)

                // Broadcast scene-space pose so peer viewports' planes
                // for this same client can mirror the move. Use
                // scenePosition/sceneRotation — they're always live;
                // intrinsicPosition isn't updated by setNodePositionFromScene
                // during a drag. Slotted planes get the same treatment
                // (receivers set isGrabbed to suspend the abductor
                // binding until the matching grab-end signal).
                if (plane.client && plane.client.internalId) {
                    PlanePoseSync.setPose(
                        "" + plane.client.internalId,
                        plane.scenePosition,
                        plane.sceneRotation,
                        plane.intrinsicCurvature)
                }

                const hits = view3d.pickAll(mouse.x, mouse.y)
                let target = null
                let action = PlaneInteractionManager.Action.None
                for (let i = 0; i < hits.length; ++i) {
                    const otherPlane = scene.planeInteraction.planeFromObject(hits[i].objectHit)
                    if (!otherPlane) continue
                    if (otherPlane === plane) continue
                    if (otherPlane._isPseudomirror) continue
                    target = otherPlane
                    action = scene.planeInteraction.uvToAction(
                        hits[i].uvPosition.x, hits[i].uvPosition.y)
                    break
                }
                scene.planeInteraction.setSnapTarget(target, action)
            } else if (mode === "orbit") {
                root._yawDeg -= dx * root._orbitSensitivity
                root._pitchDeg -= dy * root._orbitSensitivity
                if (root._pitchDeg > 89) root._pitchDeg = 89
                if (root._pitchDeg < -89) root._pitchDeg = -89
                root._updateCamera()
            } else {
                root._refreshHoveredPlane(mouse.x, mouse.y)
            }
        }

        onPressed: (mouse) => {
            lastX = mouse.x; lastY = mouse.y

            if (mouse.button === Qt.LeftButton) {
                const result = view3d.pick(mouse.x, mouse.y)
                if (result.objectHit) {
                    const plane = scene.planeInteraction.planeFromObject(result.objectHit)
                    if (plane && !plane._isPseudomirror) {
                        scene.planeInteraction.beginGrab(plane)
                        const planeView = view3d.mapFrom3DScene(plane.scenePosition)
                        grabDepth = planeView.z
                        const mouseScene = view3d.mapTo3DScene(
                            Qt.vector3d(mouse.x, mouse.y, grabDepth))
                        grabOffset = plane.scenePosition.minus(mouseScene)
                        mode = "grab"
                        return
                    }
                }
            }
            mode = "orbit"
        }

        onReleased: (mouse) => {
            if (mode === "grab") {
                const grabbedPlane = scene.planeInteraction._grabbedPlane
                scene.planeInteraction.endGrab()
                if (grabbedPlane && grabbedPlane.client && grabbedPlane.client.internalId) {
                    // Final post-snap pose for peer viewports, then signal
                    // grab end so they release isGrabbed and let their
                    // abductor binding take over.
                    PlanePoseSync.setPose(
                        "" + grabbedPlane.client.internalId,
                        grabbedPlane.scenePosition,
                        grabbedPlane.sceneRotation,
                        grabbedPlane.intrinsicCurvature)
                    PlanePoseSync.endGrab("" + grabbedPlane.client.internalId)
                }
            }
            mode = ""
        }

        onCanceled: {
            if (mode === "grab") {
                const grabbedPlane = scene.planeInteraction._grabbedPlane
                scene.planeInteraction.endGrab()
                if (grabbedPlane && grabbedPlane.client && grabbedPlane.client.internalId) {
                    PlanePoseSync.endGrab("" + grabbedPlane.client.internalId)
                }
            }
            mode = ""
        }

        onWheel: (wheel) => {
            if (wheel.modifiers & Qt.AltModifier) {
                const direction = wheel.angleDelta.y > 0 ? 1.0 : -1.0
                root._refreshHoveredPlane(wheel.x, wheel.y)
                root.curvatureNudge(direction)
                return
            }
            const factor = wheel.angleDelta.y > 0
                ? (1 - root._zoomSensitivity)
                : (1 + root._zoomSensitivity)
            root._radius = Math.max(0.5, root._radius * factor)
            root._updateCamera()
        }
    }

    // === Shortcut wiring ===
    Connections {
        target: KWinVrShortcuts
        function onResetViewTriggered() { root.resetView() }
        // Other shortcuts (grab, realign, hud-toggle) are XR-pose-specific
        // and don't have a clean 2D mapping yet — wire them as the 2D
        // interaction surface grows.
    }
}
