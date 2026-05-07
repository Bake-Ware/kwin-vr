/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * Vr2DViewport — a Plasma client window that renders the curved-plane
 * scene from a 2D-controlled orbit camera.
 *
 * Use cases:
 *   - Fallback when VR is started but no DRM lease is open (no HMD).
 *   - Future: spectator/inspector window into a live VR session.
 *   - Future: additional viewers when invited into the user's
 *     environment (local-process for now; remote via Telesthete later).
 *
 * Each viewport hosts its own WindowSceneRoot inline (XrView is a
 * QQuick3DNode and doesn't expose importScene). Same KwinWindowModel
 * sources both, so the windows shown match between modes.
 */

import QtQuick
import QtQuick.Window
import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin.vr

Window {
    id: root

    title: qsTr("KWin-VR Viewport")
    color: "skyblue"
    width: Screen.width > 1 ? Screen.width : 1280
    height: Screen.height > 1 ? Screen.height : 720
    visible: true
    visibility: Window.FullScreen

    // Closing the window deactivates VR — symmetric with HMD detach.
    onClosing: KwinVrBridge.requestVrDeactivate()

    // Esc deactivates VR. Anything else falls through.
    Item {
        id: keyHost
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: KwinVrBridge.requestVrDeactivate()
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

        // Orbit pivot. Sits at the centre of where the curved-plane
        // grabHandle is in scene-space, so the camera orbits the
        // visible cluster of windows rather than scene origin.
        Node {
            id: orbitOrigin
            position: Qt.vector3d(0, 0, -scene.distance)
        }

        // Camera starts at scene origin facing the cluster — same pose
        // the XR head would have at session start. OrbitCameraController
        // takes over once user drags.
        PerspectiveCamera {
            id: orbitCam
            position: Qt.vector3d(0, 0, 0)
            eulerRotation: Qt.vector3d(0, 0, 0)
            fieldOfView: 60
            clipNear: 0.1
            clipFar: 1000

            // HUD — head-locked overlays (panel, taskbar, notifications,
            // OSDs). Mirrors XrScene's hudNode under XrCamera; same node
            // tree, just a different camera parent.
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

    // Drag-to-orbit + wheel-to-zoom. Provided by QtQuick3D.Helpers.
    // Disabled while a left-click drag is grabbing a plane so orbit
    // doesn't fight the grab gesture.
    OrbitCameraController {
        id: orbitController
        anchors.fill: view3d
        camera: orbitCam
        origin: orbitOrigin
        enabled: !grabPicker.grabbing
    }

    // === Plane interaction helpers (mirror XrScene's API surface) ===
    //
    // KWinVrShortcuts and the wheel handlers below dispatch to these so
    // a 2D session has parity with VR shortcuts.

    // Hovered plane = first hit at current mouse pos. Refreshed on each
    // mouse move so curvatureNudge / grab can act on what's under cursor.
    property var _hoveredPlane: null

    function _refreshHoveredPlane(x, y) {
        const result = view3d.pick(x, y)
        if (!result.objectHit) {
            _hoveredPlane = null
            return
        }
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
    }

    function resetView() { scene.resetView() }

    // === Mouse-driven plane interaction ===
    MouseArea {
        id: grabPicker
        anchors.fill: view3d
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        hoverEnabled: true

        property bool grabbing: false
        property real grabDepth: 0
        property vector3d grabOffset: Qt.vector3d(0, 0, 0)

        onPositionChanged: (mouse) => {
            // Update hovered plane for shortcut targets.
            root._refreshHoveredPlane(mouse.x, mouse.y)

            if (!grabbing) {
                mouse.accepted = false
                return
            }
            const plane = scene.planeInteraction._grabbedPlane
            if (!plane) return

            const mouseScene = view3d.mapTo3DScene(Qt.vector3d(mouse.x, mouse.y, grabDepth))
            const newPos = mouseScene.plus(grabOffset)
            KwinVrHelpers.setNodePositionFromScene(plane, newPos)

            // Re-pick to identify a snap target.
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
        }

        onPressed: (mouse) => {
            const result = view3d.pick(mouse.x, mouse.y)
            if (!result.objectHit) {
                mouse.accepted = false
                return
            }
            const plane = scene.planeInteraction.planeFromObject(result.objectHit)
            if (!plane || plane._isPseudomirror) {
                mouse.accepted = false
                return
            }
            scene.planeInteraction.beginGrab(plane)
            const planeView = view3d.mapFrom3DScene(plane.scenePosition)
            grabDepth = planeView.z
            const mouseScene = view3d.mapTo3DScene(Qt.vector3d(mouse.x, mouse.y, grabDepth))
            grabOffset = plane.scenePosition.minus(mouseScene)
            grabbing = true
        }

        onReleased: (mouse) => {
            if (!grabbing) return
            scene.planeInteraction.endGrab()
            grabbing = false
        }

        onCanceled: {
            if (!grabbing) return
            scene.planeInteraction.endGrab()
            grabbing = false
        }

        // Wheel modifiers — alt = curvature nudge, others fall through to
        // OrbitCameraController for zoom.
        onWheel: (wheel) => {
            if (wheel.modifiers & Qt.AltModifier) {
                const direction = wheel.angleDelta.y > 0 ? 1.0 : -1.0
                root._refreshHoveredPlane(wheel.x, wheel.y)
                root.curvatureNudge(direction)
                wheel.accepted = true
            } else {
                wheel.accepted = false
            }
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
