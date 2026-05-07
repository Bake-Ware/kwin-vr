/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick3D
import QtQuick3D.Helpers
import QtQuick3D.Xr

import org.kde.kwin as KWinC
import org.kde.kwin.vr

XrView {
    id: xrView
    onInitializeFailed: (errorString) => KwinVrBridge.xrFailed(errorString);
    onSessionEnded: (errorString) => KwinVrBridge.xrFailed("Session ended")
    referenceSpace: XrView.ReferenceSpaceLocal
    depthSubmissionEnabled: false

    // Scene tree (registry, repeaters, prism viz). Owned by Main.qml so
    // that 0..N viewports can share it. XrScene wires viewport-specific
    // helpers (camera, spaceAllocator, followMode) on completion.
    required property WindowSceneRoot scene
    importScene: scene

    Timer {
        id: autoAlignTimer
        onTriggered: scene.resetView()
        interval: KWinVRConfig.resetViewDelay * 1000
    }
    Component.onCompleted: {
        if(KWinVRConfig.resetViewDelay >= 0)
            autoAlignTimer.start()
        // Wire scene to this viewport's helpers.
        scene.viewpoint = cam
        scene.spaceAllocator = spaceAllocator
        scene.followMode = followMode
        scene.autoAlignTimer = autoAlignTimer
        scene.focusControl = focusTracking
        scene.virtualScreenName = kvs.params.name
        scene.planeInteraction.xray = pickRay
        scene.planeInteraction.picking = focusTracking.picking
        scene.followCamera = KWinVRConfig.followEnabled
    }

    property real ppu: KWinVRConfig.ppu
    property real distance: KWinVRConfig.distance

    property alias hudEnabled: hudLoader.active
    property alias rayEnabled: pickRay.enabled
    property alias cursorEnabled: focusTracking.cursorEnabled
    property alias grabbed: pickRay.grabbedObject
    readonly property bool worldGrabbed: pickRay.grabbedObject === scene.grabHandle
    readonly property var cursorHoverObject: focusTracking.cursorHoverObject
    // Modifier state snapshotted at the most recent mouse press, set by
    // Main.qml from the synthesized QMouseEvent. Qt.application.keyboardModifiers
    // is unreliable in the VR session because the overlay doesn't hold
    // global keyboard focus.
    property bool shiftHeldOnPress: false
    property alias currentMovingResizingWindow: focusTracking.currentMovingResizingWindow
    property alias pullGrabbed: pickRay.pullGrabbed
    property alias pushGrabbed: pickRay.pushGrabbed

    property bool test1: false
    onTest1Changed: {
        KwinVrHelpers.activateOutput(kvs.output, KWinVRConfig.scale)
    }

    function die() {  }
    function resetView() { scene.resetView() }

    KwinVirtualScreenHandle {
        id: kvs
        params: KwinVrHelpers.createVirtScreenParams("T", "Virtual Screen",
                                                     Qt.size(
                                                         KWinVRConfig.width * KWinVRConfig.scale,
                                                         KWinVRConfig.height * KWinVRConfig.scale
                                                         ),
                                                     KWinVRConfig.scale,
                                                     KWinVRConfig.refreshrate * 1000)
    }

    property KwinVrInputDevice kwinInput
    property KwinVrInputFilter kwinInputFilter

    RelativeMotionBlocker {
        allowedDevice: kwinInput
    }

    VrPointerOffset {
        id: pointerOffset
        enabled: !KWinVRConfig.blockOtherPointerMotion
        vrDevice: kwinInput
        sensitivity: KWinVRConfig.mouseOffsetSensitivity
        maxOffset: KWinVRConfig.mouseOffsetMaxDegrees
    }

    // Gaze reclaim: snap pointer offset back to center when head moves past threshold
    QtObject {
        id: gazeReclaim
        property quaternion referenceRotation
        property bool hasReference: false
    }
    Connections {
        target: cam
        enabled: KWinVRConfig.gazeReclaimEnabled && pointerOffset.enabled
                 && (pointerOffset.offsetX !== 0 || pointerOffset.offsetY !== 0)
        function onSceneRotationChanged() {
            if (!gazeReclaim.hasReference) {
                gazeReclaim.referenceRotation = cam.sceneRotation
                gazeReclaim.hasReference = true
                return
            }
            const delta = KwinVrHelpers.getRotationDelta(gazeReclaim.referenceRotation, cam.sceneRotation)
            const euler = delta.toEulerAngles()
            const headMoveDeg = Math.sqrt(euler.x * euler.x + euler.y * euler.y)
            const threshold = KWinVRConfig.gazeReclaimThreshold * KWinVRConfig.mouseOffsetMaxDegrees
            if (headMoveDeg > threshold) {
                pointerOffset.reset()
            }
        }
    }
    Connections {
        target: pointerOffset
        function onOffsetChanged() {
            if (pointerOffset.offsetX === 0 && pointerOffset.offsetY === 0) {
                gazeReclaim.referenceRotation = cam.sceneRotation
                gazeReclaim.hasReference = true
            }
        }
    }

    function radialMenuActivate(pressed: bool): bool {
        if(!focusTracking.cursorHoverObject) {
            if(!pressed) {
                if(radialMenuLoader.active) {
                    radialMenuLoader.active = false
                }
                radialMenuLoader.active = true
            }
            return true;
        } else {
            radialMenuLoader.close()
            return false;
        }
    }

    function closeRadialMenu(): bool {
        if(radialMenuLoader.active) {
            radialMenuLoader.close()
            return true
        }
        return false
    }

    function realignItem() {
        const hobj = focusTracking.hoveredGrabHandle
        if(hobj) {
            KwinVrHelpers.turnToFaceKeepRoll(hobj, cam)
        }
    }

    function release(): bool {
        if(pickRay.grabbedObject) {
            pickRay.release()
            return true;
        } else {
            return false;
        }
    }

    function grab(grabAll: bool): void {
        if(pickRay.grabbedObject)
            pickRay.release()
        else
            pickRay.grab(grabAll ? scene.grabHandle : focusTracking.hoveredGrabHandle)
    }

    function grabMoveClamped(value: real, minDist: real, maxDist: real): void {
        pickRay.grabMoveClamped(value, minDist, maxDist)
    }

    // Scroll-to-depth for grabbed detached VR windows and the whole-world grab.
    // Each scroll step applies one sensitivity unit in the sign direction.
    function scrollGrab(delta: real): void {
        if (!pickRay.grabbedObject)
            return
        const isWorld = pickRay.grabbedObject === scene.grabHandle
        if (!isWorld) {
            const appWin = pickRay.grabbedObject as KwinApplicationWindow
            if (!appWin || !appWin.client || !appWin.client.vr)
                return
        }
        const direction = delta > 0 ? 1.0 : -1.0
        pickRay.grabMoveClamped(
            direction * KWinVRConfig.grabScrollSensitivity,
            KWinVRConfig.grabScrollMinDistance,
            KWinVRConfig.grabScrollMaxDistance)
    }

    // Resize grabbed VR window. dw/dh are in pixels.
    function resizeGrabbed(dw: real, dh: real): void {
        if (!pickRay.grabbedObject)
            return
        const appWin = pickRay.grabbedObject as KwinApplicationWindow
        if (!appWin || !appWin.client || !appWin.client.vr)
            return
        KwinVrHelpers.windowResize(appWin.client, dw, dh)
    }

    // Uniform scale resize for pinch gestures. scale is multiplicative (1.0 = no change).
    function pinchResizeGrabbed(scale: real): void {
        if (!pickRay.grabbedObject)
            return
        const appWin = pickRay.grabbedObject as KwinApplicationWindow
        if (!appWin || !appWin.client || !appWin.client.vr)
            return
        const sz = KwinVrHelpers.windowSize(appWin.client)
        const dw = sz.width * (scale - 1.0)
        const dh = sz.height * (scale - 1.0)
        KwinVrHelpers.windowResize(appWin.client, dw, dh)
    }

    property alias desktopOrDockHovered: focusTracking.desktopOrDockHovered
    function grabDesktop(): bool {
        if (!desktopOrDockHovered) {
            return false
        }

        if (!pickRay.grabbedObject) {
            pickRay.grab(desktopOrDockHovered.grabHandle)
            return true
        }
        return false
    }

    passthroughEnabled: KWinVRConfig.blend
    environment: SceneEnvironment {
        clearColor: "skyblue"
        backgroundMode: KWinVRConfig.blend ? SceneEnvironment.Transparent : SceneEnvironment.Color
        depthPrePassEnabled: KWinVRConfig.depthPrePassEnabled
        depthTestEnabled: KWinVRConfig.depthTestEnabled
    }

    property alias headScroll: headScroll
    VrHeadScroll {
        id: headScroll
        camera: cam
        verticalScrollMultiplier: KWinVRConfig.verticalHeadScrollSpeed
        horizontalScrollMultiplier: KWinVRConfig.horizontalHeadScrollSpeed
        threshold: KWinVRConfig.headScrollThreshold
    }

    VrFocusControl {
        id: focusTracking
        headScroll: headScroll
        kwinInput: xrView.kwinInput
        kwinInputFilter: xrView.kwinInputFilter
        cursor3d: vrCursor
        xray: pickRay
        xrView: xrView
    }

    // Forward registry alias for legacy callers.
    readonly property alias planeRegistry: scene.planeRegistry

    // Selection prism — XR ray-pick-driven gesture; state lives on the
    // shared scene so the visualisation parents under the imported tree.
    function prismBegin() {
        const p = pickRay.scenePosition.plus(pickRay.forward.times(xrView.distance))
        scene.prismBegin(p)
    }

    function prismUpdate() {
        if (!scene.prismActive) return
        const p = pickRay.scenePosition.plus(pickRay.forward.times(xrView.distance))
        scene.prismUpdate(p)
    }

    function prismCommit() { return scene.prismCommit() }
    function prismCancel() { scene.prismCancel() }

    // Alt+wheel curvature nudge on the hovered plane. Always writes the
    // per-window override (intrinsicCurvature when top-level, slot
    // override when abducted) — matches "modify while child writes the
    // override" rule from architecture.
    function curvatureNudge(direction) {
        const obj = focusTracking.hoveredGrabHandle
        const plane = scene.planeInteraction._planeFromObject(obj)
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

    VrKwinCursor {
        id: vrCursor
        ppu: xrView.ppu
        visible: false
    }

    xrOrigin: XrOrigin {
        VrInputBindings {
            kwinInput: xrView.kwinInput
        }

        camera: XrCamera {
            id: cam

            DirectionalLight {}

            /* HUD surface — grid + debug + overlay windows */
            Node {
                id: hudNode

                readonly property int dw: KWinVRConfig.width * KWinVRConfig.scale
                readonly property int dh: KWinVRConfig.height * KWinVRConfig.scale
                readonly property real surfaceW: dw / xrView.ppu * KWinVRConfig.hudScaleH
                readonly property real surfaceH: dh / xrView.ppu * KWinVRConfig.hudScaleV
                readonly property real hudDistance: KWinVRConfig.distance * KWinVRConfig.hudDistanceFraction / 100.0
                readonly property real hudY: -(hudDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))

                position: Qt.vector3d(0, hudY, -hudDistance)

                /* Grid + debug overlay (only when enabled) */
                Loader3D {
                    active: KWinVRConfig.hudEnabled || KWinVRConfig.debugDisplayEnabled
                    sourceComponent: VrHudPlane {
                        ppu: xrView.ppu
                        displayWidth: hudNode.dw
                        displayHeight: hudNode.dh
                        lastPick: focusTracking.lastPick
                    }
                }

                /* Overlay windows (dock, notifications, OSD, applets) pinned to HUD */
                Repeater3D {
                    id: hudWindowsRepeater
                    model: HudWindowFilter {
                        windowModel: applicationWindowsRepeater.windowDataModel
                        showNotifications: KWinVRConfig.hudShowNotifications
                        showOsd: KWinVRConfig.hudShowOsd
                        showDock: KWinVRConfig.hudShowDock
                        showAppletPopup: KWinVRConfig.hudShowAppletPopup
                    }
                    delegate: VrHudWindow {
                        required property QtObject window
                        client: window
                        ppu: xrView.ppu
                        hudSurfaceW: hudNode.surfaceW
                        hudSurfaceH: hudNode.surfaceH
                        hudCurvature: KWinVRConfig.hudCurvature
                    }
                }
            }

            Xray {
                id: pickRay
                camera: cam
                pointerOffsetX: pointerOffset.offsetX
                pointerOffsetY: pointerOffset.offsetY
                vrRay: VrRay {
                    depthBias: -10000 // should be always visible
                }

                Loader3D {
                    id: hudLoader
                    active: false
                    sourceComponent: XrayHud {
                        ray: pickRay
                        lastPick: focusTracking.lastPick
                        ppu: xrView.ppu
                    }
                }
            }
        }
    }

    Loader3D {
        id: radialMenuLoader
        signal close()
        active: false
        sourceComponent: RadialMenuNode {
            Component.onCompleted: {
                position = pickRay.mapPositionToNode(parent, Qt.vector3d(0,0, -(xrView.distance - 20)))
                rotation = KwinVrHelpers.targetSceneRotationToNodeRotation(this, cam)
            }

            Binding {
                target: pickRay
                property: "enabled"
                value: true
            }

            Connections {
                target: radialMenuLoader
                function onClose() { close() }
            }

            onCenterButtonClicked: close()
            onClosed: radialMenuLoader.active = false
            buttonLabels: [
                qsTr("Park Ray"),
                qsTr("Recenter"),
                qsTr("Grab All"),
                qsTr("Follow"),
                qsTr("Blend")
            ]
            buttonEnabled: [
                false,
                false,
                false,
                scene.followCamera,
                xrView.environment.backgroundMode === SceneEnvironment.Transparent
            ]
            onButtonClicked: (index) => {
                                 if(index === 0) {
                                     pickRay.enabled = false
                                     radialMenuLoader.active = false
                                 } else if(index === 1) {
                                     scene.resetView()
                                     radialMenuLoader.active = false
                                 } else if (index === 2) {
                                     xrView.grab(true)
                                     radialMenuLoader.active = false
                                 } else if (index === 3) {
                                     scene.followCamera = !scene.followCamera
                                 }  else if (index === 4) {
                                     if(xrView.environment.backgroundMode === SceneEnvironment.Transparent) {
                                         xrView.environment.backgroundMode = SceneEnvironment.Color
                                         xrView.passthroughEnabled = false
                                     } else {
                                         xrView.environment.backgroundMode = SceneEnvironment.Transparent
                                         xrView.passthroughEnabled = true
                                     }
                                 }
                             }
        }
    }


    // Camera-bound helpers — XR-only today; Vr2DViewport will instantiate
    // its own equivalents (or null-out the scene's bindings) when active.
    SpaceAllocator3D {
        id: spaceAllocator
        viewpoint: cam
        distance: xrView.distance
        spacing: 0.1
        searchGranularity: 0.1
        sizePropertyName: "itemSize"
    }

    VrFollowMode {
        id: followMode
        camera: {
            if(autoAlignTimer.running)
                return null

            if(!scene.followCamera)
                return null

            if(headScroll.headScrollActive)
                return null

            if(pickRay.grabbedObject)
                return null

            if(focusTracking.currentMovingResizingWindow)
                return null

            if(radialMenuLoader.active)
                return null

            // Do not start movement When we hover something
            // But do not stop movement when we already started
            if(focusTracking.hoveredObject && !followMode.active)
                return null

            return cam
        }
        rotationTarget: scene.grabHandle
        fovH: KWinVRConfig.followFovH
        fovV: KWinVRConfig.followFovV
        stopFovH: KWinVRConfig.followStopFovH
        stopFovV: KWinVRConfig.followStopFovV
        delay: KWinVRConfig.followDelay
        speed: KWinVRConfig.followSpeed
        worldUpAlignment: KWinVRConfig.followWorldUpAlignment
    }
}
