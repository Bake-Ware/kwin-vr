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
 * Renders the same WindowSceneRoot as XrScene via importScene. Each
 * Vr2DViewport instance has its own camera + input; the scene state is
 * shared. Single-grab is enforced by PlaneInteractionManager.
 */

import QtQuick
import QtQuick.Window
import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin.vr

Window {
    id: root

    // Shared scene to render. Must be set by the spawner.
    required property WindowSceneRoot scene

    title: qsTr("KWin-VR Viewport")
    width: 1280
    height: 720
    color: "skyblue"
    visible: true

    View3D {
        id: view3d
        anchors.fill: parent
        importScene: scene
        camera: orbitCam

        environment: SceneEnvironment {
            clearColor: "skyblue"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
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

    // === Mouse-driven plane interaction ===
    //
    // Click on a plane → grab it (PIM single-global-grab path).
    // Drag → move plane in scene at constant pick-time depth; re-pick
    // each frame to detect snap targets.
    // Release → PIM commits or settles.
    //
    // Right/middle button + empty-space drags fall through to the
    // OrbitCameraController above (we don't accept them here).
    MouseArea {
        id: grabPicker
        anchors.fill: view3d
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true

        property bool grabbing: false
        property real grabDepth: 0
        property vector3d grabOffset: Qt.vector3d(0, 0, 0)

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
            // Cache the plane's view depth so drag stays on the same parallel plane.
            const planeView = view3d.mapFrom3DScene(plane.scenePosition)
            grabDepth = planeView.z
            const mouseScene = view3d.mapTo3DScene(Qt.vector3d(mouse.x, mouse.y, grabDepth))
            grabOffset = plane.scenePosition.minus(mouseScene)
            grabbing = true
        }

        onPositionChanged: (mouse) => {
            if (!grabbing) return
            const plane = scene.planeInteraction._grabbedPlane
            if (!plane) return

            // Move plane to follow mouse at constant depth.
            const mouseScene = view3d.mapTo3DScene(Qt.vector3d(mouse.x, mouse.y, grabDepth))
            const newPos = mouseScene.plus(grabOffset)
            KwinVrHelpers.setNodePositionFromScene(plane, newPos)

            // Re-pick to identify a snap target. Walk all hits; pick the
            // first non-grabbed, non-pseudomirror plane.
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
    }
}
