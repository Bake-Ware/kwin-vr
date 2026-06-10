/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick3D
import QtQuick3D.Helpers
import QtQuick

import org.kde.kwin.vr

Model {
    id: root

    x: KWinVRConfig.headgazePositionX
    y: KWinVRConfig.headgazePositionY
    z: KWinVRConfig.headgazePositionZ
    property real pointerOffsetX: 0
    property real pointerOffsetY: 0
    eulerRotation.x: KWinVRConfig.headgazeRotationVertical + pointerOffsetY
    eulerRotation.y: KWinVRConfig.headgazeRotationHorizontal - pointerOffsetX
    property real defaultLength: 300

    property color idleColor: KWinVRConfig.headgazeColor
    property color grabbedColor: KWinVRConfig.headgazeGrabColor

    property color currentColor: grabbedObject ? grabbedColor : idleColor

    property VrRay vrRay: null
    // Duck-typed: XrCamera in XR mode, PerspectiveCamera in flat mode —
    // only Node-level APIs are used (scenePosition, mapPositionFromScene, sceneRotation).
    required property Node camera

    property Node grabbedObject: null
    property relativePose grabbedObjectPose
    property bool pullGrabbed: false
    property bool pushGrabbed: false

    property bool enabled: true

    onGrabbedObjectChanged: {
        pullGrabbed = false
        pushGrabbed = false
    }

    FrameAnimation {
        running: root.pullGrabbed
        onTriggered: root.grabMove(frameTime * 90 * +1)
    }
    FrameAnimation {
        running: root.pushGrabbed
        onTriggered: root.grabMove(frameTime * 90 * -1)
    }

    /* Set parent to us for proper projection */
    onVrRayChanged: root.vrRay ? root.vrRay.parent = this : 0

    function grab(obj: Node): void {
        if(!obj)
            return

        root.grabbedObjectPose = KwinVrHelpers.getRelativePose(root, obj)
        root.grabbedObject = obj
    }

    function grabAndAlign(obj: Node): void {
        if(!obj)
            return

        KwinVrHelpers.turnToFaceKeepRoll(obj, root.camera)

        root.grabbedObjectPose = KwinVrHelpers.getRelativePose(root, obj)
        root.grabbedObject = obj
    }

    function release(): void {
        grabbedObject = null
    }

    function grabMove(value: real): void {
        root.grabbedObjectPose.position = root.grabbedObjectPose.position.plus(Qt.vector3d(0,0, value))
        // Apply immediately: the pose is otherwise only re-applied when the
        // ray transform changes — fine with head jitter in XR, but with a
        // stationary camera (flat mode) depth changes would not show until
        // the next pointer move.
        root.applyGrab()
    }

    function grabMoveClamped(value: real, minDist: real, maxDist: real): void {
        const pos = root.grabbedObjectPose.position
        const newPos = pos.plus(Qt.vector3d(0, 0, value))
        // Distance is the length of the relative position vector
        const newDist = newPos.length()
        if (newDist < minDist || newDist > maxDist) {
            return
        }
        root.grabbedObjectPose.position = newPos
        root.applyGrab()  // see grabMove
    }

    function grabbedObjectDistance(): real {
        const pose = root.grabbedObjectPose
        const distance = pose?.position.length() ?? 0
        return distance > 0.001 ? distance : root.defaultLength
    }

    function alignGrabbedObjectToCamera(): void {
        if (!root.grabbedObject) {
            return
        }

        const distance = root.grabbedObjectDistance()
        const scenePos = root.scenePosition.plus(root.forward.times(distance))
        KwinVrHelpers.setNodePositionFromScene(root.grabbedObject, scenePos)
        KwinVrHelpers.turnToFaceKeepRoll(root.grabbedObject, root.camera)
        root.grabbedObjectPose = KwinVrHelpers.getRelativePose(root, root.grabbedObject)
    }

    function applyGrab(): void {
        if (!root.grabbedObject) {
            return
        }
        KwinVrHelpers.applyRelativePose(root, root.grabbedObject, root.grabbedObjectPose)
    }

    // Rotates the grabbed object around the camera so the xray passes through pointerPos.
    // Preserves distance object rollrelative to camera,
    // pointerPos is in scene coordinates
    function rotateGrabbedObjectAroundCameraToRay(xray: Xray, pointerPos: vector3d): bool {
        const grabbed = xray.grabbedObject
        if (!grabbed) {
            return false
        }

        xray.applyGrab()

        const cmaera = xray.camera
        const cameraPos = camera.scenePosition
        const currentSceneRot = grabbed.sceneRotation

        // Find where the xray intersects the sphere around camera at pointer distance
        const pointerDistFromCamera = camera.mapPositionFromScene(pointerPos).length()
        const t = KwinVrHelpers.raySphereIntersectFar(xray.scenePosition, xray.forward, cameraPos, pointerDistFromCamera)

        if (t < 0) {
            return false
        }

        // Compute rotation from old pointer direction to new pointer direction
        const newPointerPos = xray.scenePosition.plus(xray.forward.times(t))
        const oldPointerDir = pointerPos.minus(cameraPos).normalized()
        const newPointerDir = newPointerPos.minus(cameraPos).normalized()

        const deltaRot = KwinVrHelpers.rotationBetweenVectorsPreserveRoll(
            oldPointerDir,
            newPointerDir,
            currentSceneRot,
            camera.sceneRotation
        )

        // Apply rotation to object position and orientation (rotating around camera)
        const grabbedPosFromCamera = grabbed.scenePosition.minus(cameraPos)
        const newScenePos = cameraPos.plus(deltaRot.times(grabbedPosFromCamera))
        const newSceneRot = deltaRot.times(currentSceneRot)

        KwinVrHelpers.setNodePositionFromScene(grabbed, newScenePos)
        KwinVrHelpers.setNodeRotationFromScene(grabbed, newSceneRot)

        // Update the pose relative to xray
        xray.grabbedObjectPose = KwinVrHelpers.getRelativePose(xray, grabbed)
        return true
    }

    Connections {
        target: root
        enabled: root.grabbedObject !== null
        function onSceneTransformChanged(): void {
            KwinVrHelpers.applyRelativePose(root, root.grabbedObject, root.grabbedObjectPose)
        }
    }
}
