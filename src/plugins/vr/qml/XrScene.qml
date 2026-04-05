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
    onInitializeFailed: (errorString) => kwinVrBridge.xrFailed(errorString);
    onSessionEnded: (errorString) => kwinVrBridge.xrFailed("Session ended")

    // Health ping: lets the C++ watchdog detect XR_ERROR_INSTANCE_LOST spin loops
    // (Qt's XrView does not emit onSessionEnded for runtime crashes/restarts)
    Timer {
        id: healthPing
        interval: 5000
        repeat: true
        running: true
        onTriggered: kwinVrBridge.xrPing()
    }
    referenceSpace: XrView.ReferenceSpaceLocal
    depthSubmissionEnabled: false

    Timer {
        id: autoAlignTimer
        onTriggered: allWindows.resetView()
        interval: KWinVRConfig.resetViewDelay * 1000
    }
    Component.onCompleted: {
        if(KWinVRConfig.resetViewDelay >= 0)
            autoAlignTimer.start()
    }

    property real ppu: KWinVRConfig.ppu
    property real distance: KWinVRConfig.distance

    // HUD dock geometry (taskbar pinned to camera in immersive mode)
    readonly property real hudDockDistance: distance * KWinVRConfig.hudDistanceFraction / 100.0
    readonly property real hudDockY: -(hudDockDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))
    readonly property real hudDockScale: KWinVRConfig.hudScale

    property alias hudEnabled: hudLoader.active
    property alias rayEnabled: pickRay.enabled
    property alias grabbed: pickRay.grabbedObject
    property alias currentMovingResizingWindow: focusTracking.currentMovingResizingWindow
    property alias pullGrabbed: pickRay.pullGrabbed
    property alias pushGrabbed: pickRay.pushGrabbed
    property alias curveBigger: pickRay.curveBigger
    property alias curveSmaller: pickRay.curveSmaller
    property alias resizeRight: pickRay.resizeRight
    property alias resizeLeft: pickRay.resizeLeft
    property alias resizeUp: pickRay.resizeUp
    property alias resizeDown: pickRay.resizeDown

    // PIP state — HUD-style: parented to camera at comfortable distance,
    // always renders on top via zOffsetGlobal depth bias
    property Node pipTarget: null
    property vector3d pipPosition: Qt.vector3d(12, -8, -30)
    property bool pipHasPosition: false
    readonly property real pipDistance: xrView.distance * 0.7
    readonly property real pipScale: 0.25
    property bool pipGrabActive: false
    readonly property bool pipGrabbed: pipGrabActive && pipTarget !== null
    property real pipSavedCurvature: 0
    property real pipCurvature: 0

    // PIP arrow-key movement (camera-local)
    property bool pipMoveRight: false
    property bool pipMoveLeft: false
    property bool pipMoveUp: false
    property bool pipMoveDown: false

    FrameAnimation {
        running: xrView.pipMoveRight
        onTriggered: { var p = xrView.pipPosition; p.x += frameTime * 30; xrView.pipPosition = p }
    }
    FrameAnimation {
        running: xrView.pipMoveLeft
        onTriggered: { var p = xrView.pipPosition; p.x -= frameTime * 30; xrView.pipPosition = p }
    }
    FrameAnimation {
        running: xrView.pipMoveUp
        onTriggered: { var p = xrView.pipPosition; p.y += frameTime * 30; xrView.pipPosition = p }
    }
    FrameAnimation {
        running: xrView.pipMoveDown
        onTriggered: { var p = xrView.pipPosition; p.y -= frameTime * 30; xrView.pipPosition = p }
    }

    function togglePip(): void {
        if (pipTarget) {
            // Save PIP position/curvature for next PIP session
            pipPosition = pipTarget.position
            pipCurvature = pipTarget.curvature ?? 0
            // Restore original window curvature
            pipTarget.curvature = pipSavedCurvature
            pipGrabActive = false
            pipTarget = null
        } else {
            const target = focusTracking.hoveredGrabHandle
            if (!target) return
            pipSavedCurvature = target.curvature ?? 0
            if (!pipHasPosition) {
                pipPosition = Qt.vector3d(12, -8, -pipDistance)
                pipHasPosition = true
            }
            pipTarget = target
        }
    }

    function die() {  }
    function resetView() { allWindows.resetView() }

    KwinVirtualScreenHandle {
        id: kvs
        params: KwinVrHelpers.createVirtScreenParams("T", "Virtual Screen",
                                                     Qt.size(
                                                         KWinVRConfig.width * KWinVRConfig.scale,
                                                         KWinVRConfig.height * KWinVRConfig.scale
                                                         ),
                                                     KWinVRConfig.scale)
        // When the virtual output is ready, make it the primary display and
        // move headset outputs (KWIN_FORCE_DESKTOP_OUTPUTS) off-screen so
        // windows and snap targets land on the virtual desktop, not the headset.
        onOutputChanged: {
            if (kvs.output)
                KwinVrHelpers.activateOutput(kvs.output, KWinVRConfig.scale)
        }
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

    function toggleRadialMenu(): void {
        if (radialMenuLoader.active) {
            radialMenuLoader.close()
        } else {
            radialMenuLoader.active = true
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
        if (pipGrabActive) {
            pipGrabActive = false
            return true
        }
        if(pickRay.grabbedObject) {
            pickRay.release()
            return true;
        } else {
            return false;
        }
    }

    // Grabs allWindowsGrabHandle only if cursor is over empty space.
    // Returns true if the grab was initiated, false if cursor is over a window.
    function grabAllWindows(): bool {
        if (focusTracking.cursorHoverObject) return false
        if (!pickRay.grabbedObject) {
            pickRay.grab(allWindowsGrabHandle)
        }
        return true
    }

    function grab(grabAll: bool): void {
        if (pipGrabActive) {
            pipGrabActive = false
            return
        }
        if(pickRay.grabbedObject) {
            pickRay.release()
        } else {
            const target = grabAll ? allWindowsGrabHandle : focusTracking.hoveredGrabHandle
            if (target)
                pickRay.grab(target)
            else if (pipTarget)
                pipGrabActive = true
        }
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
        antialiasingMode: SceneEnvironment.NoAA
        temporalAaEnabled: false
        aoEnabled: false
    }

    property alias headScrollActive: headScroll.headScrollActive

    // Head-as-mouse cursor lock mode: toggled by pressing the head-scroll key over empty space.
    // World spatial position locks, head rotation drives cursor position directly.
    property bool headLookCursorToggle: false
    property quaternion headLookInitialRotation
    property real headLookLastPitch: 0
    property real headLookLastYaw: 0

    // Disable ray picking while cursor lock is active (cursor position managed by head rotation)
    Binding {
        target: focusTracking
        property: "headLookCursorMode"
        value: xrView.headLookCursorToggle
    }

    // Toggle cursor lock on each head-scroll button press
    Connections {
        target: headScroll
        function onHeadScrollActiveChanged() {
            if (!headScroll.headScrollActive) return
            if (xrView.headLookCursorToggle) {
                // Second press: exit cursor lock, snap to center
                xrView.headLookCursorToggle = false
                xrView.kwinInput.pointerPosition = Qt.point(
                    KWinVRConfig.width * KWinVRConfig.scale / 2,
                    KWinVRConfig.height * KWinVRConfig.scale / 2
                )
            } else if (!focusTracking.cursorHoverObject) {
                // First press over empty space: enter cursor lock
                xrView.headLookCursorToggle = true
                xrView.headLookInitialRotation = cam.sceneRotation
                xrView.headLookLastPitch = 0
                xrView.headLookLastYaw = 0
            }
            // Pressed over a window: normal head scroll, do nothing extra
        }
    }

    // Head-as-mouse: camera rotation → cursor position while cursor lock is active
    Connections {
        target: cam
        enabled: xrView.headLookCursorToggle
        function onSceneRotationChanged() {
            const angles = KwinVrHelpers.headAnglesFromInitialRotation(
                xrView.headLookInitialRotation, cam.sceneRotation)
            const pitchDiff = angles.x - xrView.headLookLastPitch
            const yawDiff = angles.y - xrView.headLookLastYaw
            const thr = KWinVRConfig.headScrollThreshold
            if (Math.abs(pitchDiff) < thr && Math.abs(yawDiff) < thr) return
            const pxPerDeg = xrView.distance * xrView.ppu * Math.PI / 180
            const w = KWinVRConfig.width * KWinVRConfig.scale
            const h = KWinVRConfig.height * KWinVRConfig.scale
            xrView.kwinInput.pointerPosition = Qt.point(
                Math.max(0, Math.min(w, xrView.kwinInput.pointerPosition.x + yawDiff * pxPerDeg)),
                Math.max(0, Math.min(h, xrView.kwinInput.pointerPosition.y - pitchDiff * pxPerDeg))
            )
            xrView.headLookLastPitch = angles.x
            xrView.headLookLastYaw = angles.y
        }
    }

    VrHeadScroll {
        id: headScroll
        camera: cam
        verticalScrollMultiplier: KWinVRConfig.verticalHeadScrollSpeed
        horizontalScrollMultiplier: KWinVRConfig.horizontalHeadScrollSpeed
        threshold: KWinVRConfig.headScrollThreshold
        onWheel: (v) => {
            // Suppress scroll when cursor lock is active (head rotation handles cursor instead)
            if (!xrView.headLookCursorToggle) {
                xrView.kwinInput.setAxis(v.x, v.y)
            }
        }
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

    VrKwinCursor {
        id: vrCursor
        ppu: xrView.ppu
        visible: false
    }

    // System info stats backend
    KwinVrSysInfo {
        id: sysInfo
        active: KWinVRConfig.sysInfoEnabled
    }

    xrOrigin: XrOrigin {
        VrInputBindings {
            kwinInput: xrView.kwinInput
        }

        camera: XrCamera {
            id: cam

            DirectionalLight {}

            VrVignette {
                visible: KWinVRConfig.vignetteEnabled
                fadeWidth: KWinVRConfig.vignetteFadeWidth
            }

            // System info HUD — pinned to camera, upper-left of view
            VrSysInfoHud {
                visible: KWinVRConfig.sysInfoEnabled
                sysInfo: sysInfo
                cmWidth: KWinVRConfig.sysInfoWidth
                hudPosition: Qt.vector3d(
                    KWinVRConfig.sysInfoPositionX,
                    KWinVRConfig.sysInfoPositionY,
                    -(KWinVRConfig.sysInfoDistance > 0
                      ? KWinVRConfig.sysInfoDistance
                      : xrView.hudDockDistance)
                )
            }

            // FrameAnimation to feed frame timing into sysInfo
            FrameAnimation {
                running: KWinVRConfig.sysInfoEnabled
                onTriggered: sysInfo.recordFrame(frameTime)
            }

            /* Draw OSD windows in front of user */
            VrOsdWindows {
                windowModel: applicationWindowsRepeater.windowDataModel
                ppu: xrView.ppu
                position: Qt.vector3d(0, 5, -(xrView.distance - 20))
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
                pickRay.enabled: true
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
                allWindows.followCamera,
                xrView.environment.backgroundMode === SceneEnvironment.Transparent
            ]
            onButtonClicked: (index) => {
                                 if(index === 0) {
                                     pickRay.enabled = false
                                     radialMenuLoader.active = false
                                 } else if(index === 1) {
                                     allWindows.resetView()
                                     radialMenuLoader.active = false
                                 } else if (index === 2) {
                                     xrView.grab(true)
                                     radialMenuLoader.active = false
                                 } else if (index === 3) {
                                     allWindows.followCamera = !allWindows.followCamera
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


    Node {
        id: allWindows
        property real ppu: xrView.ppu
        property bool followCamera: false
        Component.onCompleted: followCamera = KWinVRConfig.followEnabled
        onFollowCameraChanged: followCamera ? (allWindows.position = cam.scenePosition) : null

        function resetView() {
            allWindows.position = cam.scenePosition
            const targetPos = cam.mapPositionToScene(Qt.vector3d(0, 0, -xrView.distance))
            KwinVrHelpers.setNodePositionFromScene(allWindowsGrabHandle, targetPos)
            // Maybe to respect followMode's followWorldUpAlignment ?
            KwinVrHelpers.setNodeRotationFromScene(allWindowsGrabHandle, cam.sceneRotation)
        }

        Connections {
            target: cam
            enabled: allWindows.followCamera
            function onScenePositionChanged() {
                allWindows.position = cam.scenePosition
            }
        }

        VrFollowMode {
            id: followMode
            camera: {
                if(autoAlignTimer.running)
                    return null

                if(!allWindows.followCamera)
                    return null

                if(headScroll.headScrollActive)
                    return null

                if(xrView.headLookCursorToggle)
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
            rotationTarget: allWindowsGrabHandle
            fovH: KWinVRConfig.followFovH
            fovV: KWinVRConfig.followFovV
            stopFovH: KWinVRConfig.followStopFovH
            stopFovV: KWinVRConfig.followStopFovV
            delay: KWinVRConfig.followDelay
            speed: KWinVRConfig.followSpeed
            worldUpAlignment: KWinVRConfig.followWorldUpAlignment
        }

        Node {
            id: allWindowsGrabHandle
            position: Qt.vector3d(0, 0, -xrView.distance)

            // Cursor lock indicator: white sphere at cursor position on the virtual screen plane
            Model {
                visible: xrView.headLookCursorToggle
                source: "#Sphere"
                depthBias: -9000
                position: Qt.vector3d(
                    (xrView.kwinInput.pointerPosition.x - KWinVRConfig.width  * KWinVRConfig.scale / 2) / xrView.ppu,
                    -(xrView.kwinInput.pointerPosition.y - KWinVRConfig.height * KWinVRConfig.scale / 2) / xrView.ppu,
                    0.5
                )
                scale: Qt.vector3d(0.4, 0.4, 0.4)
                materials: PrincipledMaterial {
                    baseColor: "#ffffff"
                    lighting: PrincipledMaterial.NoLighting
                    opacity: 0.85
                }
            }

            SpaceAllocator3D {
                id: spaceAllocator
                viewpoint: cam
                distance: xrView.distance
                spacing: 0.1
                searchGranularity: 0.1
                sizePropertyName: "itemSize"
            }

            Repeater3D {
                id: outputMirrorRepeater
                model: OutputModel {}
                delegate: KwinPseudoOutputMirror {
                    id: pseudoOutput
                    ppu: allWindows.ppu
                    // Hidden in immersive mode: windows float freely, but the node stays
                    // alive so window sizing/placement geometry remains available.
                    visible: !KWinVRConfig.immersiveMode
                    Component.onCompleted: {
                        const globalPosition = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                        const localPosition = outputMirrorRepeater.mapPositionFromScene(globalPosition)
                        position = localPosition
                        KwinVrHelpers.turnToFaceKeepRoll(pseudoOutput, spaceAllocator.viewpoint)
                        spaceAllocator.registerObject(pseudoOutput)
                        followMode.registerObject(pseudoOutput)
                    }
                }
                function findPseudoOutputByOutput(output: QtObject): KwinPseudoOutputMirror {
                    for(const child of this.children) {
                        const pseudoMirror = child as KwinPseudoOutputMirror
                        if(pseudoMirror && pseudoMirror.output === output) {
                            return pseudoMirror
                        }
                    }
                    return null
                }
            }

            Repeater3D {
                id: applicationWindowsRepeater
                property KwinWindowModel windowDataModel: KwinWindowModel {}

                model: PrimaryWindowModelFilter {
                    windowModel: applicationWindowsRepeater.windowDataModel
                }
                delegate: KwinApplicationWindow {
                    id: kwinAppWindow
                    required property int index
                    required property QtObject window
                    parent: null
                    client: window
                    windowDataModel: applicationWindowsRepeater.windowDataModel
                    ppu: allWindows.ppu
                    focusControl: focusTracking
                    property real zOffset: 0
                    property int stackingOrder: client.stackingOrder
                    // Tracks whether VR mode was forced on by immersive mode (not manually set)
                    property bool autoVr: false

                    function centerOffset(childRect: rect, parentRect: rect, zValue: real, ppu: real): vector3d {
                        return Qt.vector3d(
                                    +(childRect.x + childRect.width/2 - parentRect.x - parentRect.width/2)/ppu,
                                    -(childRect.y + childRect.height/2 - parentRect.y - parentRect.height/2)/ppu,
                                    zValue)
                    }

                    //For the space allocator
                    property size itemSize: {
                        if(!parent) {
                            return Qt.size(0,0)
                        }
                        const sz = client.frameGeometry;
                        return Qt.size(sz.width / kwinAppWindow.ppu, sz.height / kwinAppWindow.ppu);
                    }

                    function registerForSpaceAllocator() {
                        if (!spaceAllocator) return
                        if (client.vr) {
                            // Find a free position and orient the window in 3D space
                            const pos = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                            kwinAppWindow.position = allWindowsGrabHandle.mapPositionFromScene(pos)
                            KwinVrHelpers.turnToFaceKeepRoll(kwinAppWindow, spaceAllocator.viewpoint)
                        }
                        spaceAllocator.registerObject(kwinAppWindow)
                    }
                    // Returns true if this window should be forced into VR in immersive mode.
                    // Skips desktop backgrounds and non-app Plasma infrastructure.
                    function immersiveVrEligible(): bool {
                        if (client.dock) return true
                        if (client.desktopWindow) return false
                        return client.normalWindow || client.dialog
                    }

                    Component.onCompleted: {
                        if (KWinVRConfig.immersiveMode) {
                            if (!kwinAppWindow.immersiveVrEligible()) return
                            // Force app windows into VR space; dock is handled by "hud" state
                            client.vr = true
                            kwinAppWindow.autoVr = true
                            if (!client.dock)
                                Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                        } else if (KwinVrHelpers.hasVrPose(client)) {
                            client.vr = true
                            Qt.callLater(function() {
                                if (!kwinAppWindow) return
                                kwinAppWindow.position = KwinVrHelpers.vrPosePosition(client)
                                kwinAppWindow.rotation = KwinVrHelpers.vrPoseRotation(client)
                                kwinAppWindow.curvature = KwinVrHelpers.vrPoseCurvature(client)
                            })
                        } else {
                            Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                        }
                    }
                    Component.onDestruction: {
                        if (KWinVRConfig.immersiveMode) {
                            // Restore to flat mode on VR exit; don't save poses
                            client.vr = false
                        } else if (client.vr) {
                            KwinVrHelpers.saveVrPose(client, position, rotation, curvature)
                        }
                    }

                    Connections {
                        target: KWinVRConfig
                        function onImmersiveModeChanged() {
                            if (KWinVRConfig.immersiveMode) {
                                if (!kwinAppWindow.immersiveVrEligible()) return
                                client.vr = true
                                kwinAppWindow.autoVr = true
                                if (!client.dock)
                                    Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                            } else if (kwinAppWindow.autoVr) {
                                client.vr = false
                                kwinAppWindow.autoVr = false
                            }
                        }
                    }

                    VrWindowControls {
                        id: windowControls
                        visible: kwinAppWindow.client.vr
                                 && kwinAppWindow !== xrView.pipTarget
                                 && focusTracking.hoveredGrabHandle === kwinAppWindow
                        ppu: kwinAppWindow.ppu
                        client: kwinAppWindow.client
                        windowNode: kwinAppWindow
                        curvature: kwinAppWindow.curvature
                        onGrabRequested: pickRay.grab(kwinAppWindow)
                        onCurveChanged: (delta) => {
                            kwinAppWindow.curvature = Math.max(0, Math.min(6, kwinAppWindow.curvature + delta))
                        }
                        onPipRequested: {
                            // Save current PIP state if switching windows
                            if (xrView.pipTarget) {
                                xrView.pipPosition = xrView.pipTarget.position
                                xrView.pipCurvature = xrView.pipTarget.curvature ?? 0
                                xrView.pipTarget.curvature = xrView.pipSavedCurvature
                            }
                            xrView.pipSavedCurvature = kwinAppWindow.curvature ?? 0
                            if (!xrView.pipHasPosition) {
                                xrView.pipPosition = Qt.vector3d(12, -8, -xrView.pipDistance)
                                xrView.pipHasPosition = true
                            }
                            xrView.pipTarget = kwinAppWindow
                        }
                    }

                    states: [
                        State {
                            name: "pip"
                            when: kwinAppWindow === xrView.pipTarget &&
                                  !(KWinVRConfig.immersiveMode && kwinAppWindow.client.dock)
                            PropertyChanges {
                                kwinAppWindow {
                                    parent: cam
                                    grabHandle: kwinAppWindow
                                    zOffsetGlobal: 100
                                    position: xrView.pipPosition
                                    eulerRotation: Qt.vector3d(0, 0, 0)
                                    scale: Qt.vector3d(xrView.pipScale, xrView.pipScale, xrView.pipScale)
                                    curvature: xrView.pipCurvature
                                }
                            }
                            StateChangeScript {
                                script: followMode.unregisterObject(kwinAppWindow)
                            }
                        },
                        State {
                            name: "hud"
                            when: KWinVRConfig.immersiveMode && kwinAppWindow.client.dock
                            PropertyChanges {
                                kwinAppWindow {
                                    parent: cam
                                    grabHandle: kwinAppWindow
                                    zOffsetGlobal: 50
                                    position: Qt.vector3d(0, xrView.hudDockY, -xrView.hudDockDistance)
                                    eulerRotation: Qt.vector3d(0, 0, 0)
                                    scale: Qt.vector3d(xrView.hudDockScale, xrView.hudDockScale, xrView.hudDockScale)
                                    curvature: KWinVRConfig.defaultCurvature
                                }
                            }
                            StateChangeScript {
                                script: followMode.unregisterObject(kwinAppWindow)
                            }
                        },
                        State {
                            name: "vr"
                            when: kwinAppWindow.client.vr
                            PropertyChanges {
                                kwinAppWindow {
                                    parent: allWindowsGrabHandle
                                    grabHandle: kwinAppWindow
                                    zOffsetGlobal: 0
                                }
                            }
                            StateChangeScript {
                                script: {
                                    followMode.registerObject(kwinAppWindow)
                                    if (!KwinVrHelpers.hasVrPose(kwinAppWindow.client))
                                        kwinAppWindow.curvature = KWinVRConfig.defaultCurvature
                                }
                            }
                        },
                        State {
                            name: "hiddenScreen"
                            when: !kwinAppWindow.client.vr && KWinVRConfig.immersiveMode
                            PropertyChanges {
                                kwinAppWindow {
                                    parent: allWindowsGrabHandle
                                    grabHandle: null
                                    position: Qt.vector3d(0, -100000, 0)
                                }
                                restoreEntryValues: false
                            }
                            StateChangeScript {
                                script: followMode.unregisterObject(kwinAppWindow)
                            }
                        },
                        State {
                            name: "screen"
                            when: !kwinAppWindow.client.vr
                            PropertyChanges {
                                kwinAppWindow {
                                    parent: outputMirrorRepeater.findPseudoOutputByOutput(kwinAppWindow.client.output)
                                    grabHandle: kwinAppWindow.parent
                                    position: kwinAppWindow.centerOffset(
                                                  kwinAppWindow.client.frameGeometry,
                                                  kwinAppWindow.client.output.geometry,
                                                  kwinAppWindow.zOffset,
                                                  allWindows.ppu)
                                    rotation: Qt.quaternion(1,0,0,0)
                                }
                                restoreEntryValues: false
                            }
                            StateChangeScript {
                                script: followMode.unregisterObject(kwinAppWindow)
                            }
                        }
                    ]
                }
            }
        }
    }
}
