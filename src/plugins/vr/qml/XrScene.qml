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

    property alias hudEnabled: hudLoader.active
    property alias rayEnabled: pickRay.enabled
    property alias cursorEnabled: focusTracking.cursorEnabled
    property alias grabbed: pickRay.grabbedObject
    property alias currentMovingResizingWindow: focusTracking.currentMovingResizingWindow
    property alias pullGrabbed: pickRay.pullGrabbed
    property alias pushGrabbed: pickRay.pushGrabbed

    // Universal selection — Super+click or both-click toggles gizmo on any scene object
    property Node selectedNode: null
    property bool gizmoDragging: false
    property vector3d gizmoDragPlaneCenter: Qt.vector3d(0, 0, 0)
    // Dynamically created gizmo instance (parented to selectedNode)
    property var transformGizmo: null
    property var _gizmoInstance: null
    // Target node for context-sensitive radial menu (set before opening)
    property Node radialMenuTargetNode: null

    Component { id: gizmoComponent; TransformGizmo3D {} }

    // Saved scene pose of the focused window. On focus we slide the window
    // along its direction-from-camera to the sibling-average depth and
    // re-face it to the camera, preserving its angular position in the
    // user's surroundings. On defocus we restore.
    property var _focusedPullPose: null

    function _restoreFocusedPullPose() {
        if (!_focusedPullPose)
            return
        const pose = _focusedPullPose
        _focusedPullPose = null
        if (pose.window && pose.window.client && pose.window.client.vr) {
            KwinVrHelpers.setNodePositionFromScene(pose.window, pose.position)
            KwinVrHelpers.setNodeRotationFromScene(pose.window, pose.rotation)
        }
    }

    // Average distance from camera to every vr-floating window, excluding
    // the target. Used as depth target for the focus pull.
    function _averageFloatingDistance(exclude) {
        const camPos = cam.scenePosition
        let total = 0.0
        let count = 0
        for (let i = 0; i < applicationWindowsRepeater.count; ++i) {
            const w = applicationWindowsRepeater.objectAt(i)
            if (!w || w === exclude) continue
            if (!w.client || !w.client.vr) continue
            if (!w.visible) continue
            total += w.scenePosition.minus(camPos).length()
            count += 1
        }
        return count === 0 ? xrView.distance : total / count
    }

    // Focus pull: slide the window along its cam→window direction to the
    // sibling-average depth, and re-face it to the user. Angular position
    // in the user's surroundings is preserved (no teleport to center).
    function pullAppWinForward(appWin) {
        if (!appWin || !appWin.client || !appWin.client.vr)
            return
        if (_focusedPullPose && _focusedPullPose.window === appWin)
            return
        _restoreFocusedPullPose()

        const camPos = cam.scenePosition
        const windowPos = appWin.scenePosition
        let dir = windowPos.minus(camPos)
        const currentDist = dir.length()
        if (currentDist < 0.0001)
            return
        dir = dir.times(1.0 / currentDist)

        _focusedPullPose = {
            window: appWin,
            position: windowPos,
            rotation: appWin.sceneRotation
        }

        const avgDist = _averageFloatingDistance(appWin)
        const newPos = camPos.plus(dir.times(avgDist))
        KwinVrHelpers.setNodePositionFromScene(appWin, newPos)
        KwinVrHelpers.turnToFace(appWin, cam)

        // Animate world rotation so the focused window is centered in view.
        // Uses follow-mode's speed (KWinVRConfig.followSpeed). No-op if the
        // window is already within the reactive FOV. Passes cam explicitly
        // because followMode.camera gets null-gated during hover/grab/menu.
        followMode.focusOn(appWin, cam)
    }

    onSelectedNodeChanged: {
        _restoreFocusedPullPose()
        if (_gizmoInstance) {
            _gizmoInstance.destroy()
            _gizmoInstance = null
            transformGizmo = null
        }
        if (selectedNode) {
            const isWin = !!(selectedNode as KwinApplicationWindow)
            _gizmoInstance = gizmoComponent.createObject(selectedNode, {
                targetNode: selectedNode,
                isWindow: isWin,
                isFlatGeometry: isWin
            })
            if (isWin) {
                _gizmoInstance.windowResizeRequested.connect(function(dw, dh) {
                    const appWin = selectedNode as KwinApplicationWindow
                    if (appWin && appWin.client && appWin.client.vr)
                        KwinVrHelpers.windowResize(appWin.client, dw, dh)
                })
                pullAppWinForward(selectedNode as KwinApplicationWindow)
            }
            transformGizmo = _gizmoInstance
        }
    }

    // If the user grabs the focused-pulled window, grab becomes authoritative.
    // Drop the saved pose so deselect doesn't snap it back behind the user.
    Connections {
        target: pickRay
        function onGrabbedObjectChanged() {
            if (xrView._focusedPullPose
                && pickRay.grabbedObject === xrView._focusedPullPose.window) {
                xrView._focusedPullPose = null
            }
        }
    }

    property bool test1: false
    onTest1Changed: {
        KwinVrHelpers.activateOutput(kvs.output, KWinVRConfig.scale)
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

    // Open radial menu with context-sensitive items based on what's under cursor
    function openRadialMenuAtCursor(): void {
        // End any in-flight gizmo drag so stale activeHandle can't keep tracking
        if (gizmoDragging)
            endGizmoDrag()
        const picks = focusTracking.picking.lastAllPicks
        radialMenuTargetNode = null
        for (const pick of picks) {
            const obj = pick.objectHit
            if (!obj) continue
            if (obj.handleId !== undefined) continue
            let node = obj
            while (node) {
                if (node.grabHandle && isSceneObject(node.grabHandle)) {
                    radialMenuTargetNode = node.grabHandle
                    break
                }
                node = node.parent
            }
            if (radialMenuTargetNode) break
        }
        if (radialMenuLoader.active)
            radialMenuLoader.active = false
        radialMenuLoader.active = true
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
            pickRay.grab(grabAll ? allWindowsGrabHandle : focusTracking.hoveredGrabHandle)
    }

    // Both-click: select whatever scene object is under the cursor (shows gizmo)
    function selectObjectAtCursor(): void {
        const picks = focusTracking.picking.lastAllPicks
        for (const pick of picks) {
            const obj = pick.objectHit
            if (!obj) continue

            // Skip gizmo handles — don't select the gizmo itself
            if (obj.handleId !== undefined) continue

            // Walk up from hit to find a grab handle that lives in the scene
            let node = obj
            while (node) {
                if (node.grabHandle && isSceneObject(node.grabHandle)) {
                    const target = node.grabHandle
                    // Toggle: if already selected, deselect
                    if (selectedNode === target) {
                        selectedNode = null
                        return
                    }
                    selectedNode = target
                    return
                }
                node = node.parent
            }
        }
        // Nothing hit — deselect
        selectedNode = null
    }

    // Check if a node is part of the scene (under allWindowsGrabHandle)
    function isSceneObject(node: Node): bool {
        let n = node
        while (n) {
            if (n === allWindowsGrabHandle) return true
            n = n.parent
        }
        return false
    }

    // Check if a gizmo handle was clicked — scans ALL picks for handleId
    // regardless of distance, giving gizmo handles pick priority
    function tryGizmoHandlePress(): bool {
        if (!selectedNode || !transformGizmo) return false
        const picks = focusTracking.picking.lastAllPicks
        for (const pick of picks) {
            const obj = pick.objectHit
            if (obj && obj.handleId !== undefined) {
                // Confirm button — deselect and close gizmo
                if (obj.handleId === "confirmGizmo") {
                    selectedNode = null
                    return true
                }
                gizmoDragPlaneCenter = pick.scenePosition
                const localPos = allWindowsGrabHandle.mapPositionFromScene(pick.scenePosition)
                transformGizmo.beginDrag(obj.handleId, localPos)
                gizmoDragging = true
                return true
            }
        }
        return false
    }

    function endGizmoDrag(): void {
        if (transformGizmo) transformGizmo.endDrag()
        gizmoDragging = false
    }

    function grabMoveClamped(value: real, minDist: real, maxDist: real): void {
        pickRay.grabMoveClamped(value, minDist, maxDist)
    }

    // Grab everything when clicking on empty space (no hover target)
    function grabAllIfEmptySpace(): bool {
        if (!focusTracking.cursorHoverObject && !pickRay.grabbedObject) {
            pickRay.grab(allWindowsGrabHandle)
            return true
        }
        return false
    }

    // Scroll-to-depth for any grabbed object.
    // Each scroll step applies one sensitivity unit in the sign direction.
    function scrollGrab(delta: real): void {
        if (!pickRay.grabbedObject)
            return
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
                        showDialog: true
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
            onClosed: {
                radialMenuLoader.active = false
                xrView.radialMenuTargetNode = null
            }
            menuItems: {
                var items = []
                if (xrView.radialMenuTargetNode)
                    items.push({ label: qsTr("Transform"), action: "transform" })
                if (xrView.selectedNode)
                    items.push({ label: qsTr("Done"), action: "confirmGizmo" })
                return items.concat([
                    { label: qsTr("Park Ray"),  action: "parkRay" },
                    { label: qsTr("Recenter"),  action: "recenter" },
                    { label: qsTr("Grab All"),  action: "grabAll" },
                    { label: qsTr("Follow"),    action: "follow",  enabled: allWindows.followCamera },
                    { label: qsTr("Blend"),     action: "blend",   enabled: xrView.environment.backgroundMode === SceneEnvironment.Transparent }
                ])
            }
            onActionTriggered: (action) => {
                                   console.log(Logger.kwinvr, "RadialMenu actionTriggered:", action)
                                   if (action === "transform") {
                                       if (xrView.radialMenuTargetNode)
                                           xrView.selectedNode = xrView.radialMenuTargetNode
                                       radialMenuLoader.active = false
                                   } else if (action === "confirmGizmo") {
                                       xrView.selectedNode = null
                                       radialMenuLoader.active = false
                                   } else if (action === "parkRay") {
                                       pickRay.enabled = false
                                       radialMenuLoader.active = false
                                   } else if (action === "recenter") {
                                       allWindows.resetView()
                                       radialMenuLoader.active = false
                                   } else if (action === "grabAll") {
                                       xrView.grab(true)
                                       radialMenuLoader.active = false
                                   } else if (action === "follow") {
                                       allWindows.followCamera = !allWindows.followCamera
                                   } else if (action === "blend") {
                                       if (xrView.environment.backgroundMode === SceneEnvironment.Transparent) {
                                           xrView.environment.backgroundMode = SceneEnvironment.Color
                                           xrView.passthroughEnabled = false
                                       } else {
                                           xrView.environment.backgroundMode = SceneEnvironment.Transparent
                                           xrView.passthroughEnabled = true
                                       }
                                   }
                               }
            // Legacy handler kept for backward compatibility
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
                // Map of output → pseudomirror, survives parent:null hiding
                property var outputMap: ({})
                model: OutputModel {}
                delegate: KwinPseudoOutputMirror {
                    id: pseudoOutput
                    readonly property bool isVirtualHidden: output.name === ("Virtual-" + kvs.params.name) && KWinVRConfig.hideVirtualDisplay
                    // Remove from scene graph entirely when hidden
                    parent: isVirtualHidden ? null : outputMirrorRepeater
                    ppu: allWindows.ppu
                    Component.onCompleted: {
                        outputMirrorRepeater.outputMap[output.name] = pseudoOutput
                        const globalPosition = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                        const localPosition = outputMirrorRepeater.mapPositionFromScene(globalPosition)
                        position = localPosition
                        KwinVrHelpers.turnToFaceKeepRoll(pseudoOutput, spaceAllocator.viewpoint)
                        spaceAllocator.registerObject(pseudoOutput)
                        followMode.registerObject(pseudoOutput)
                    }
                    Component.onDestruction: {
                        delete outputMirrorRepeater.outputMap[output.name]
                        spaceAllocator.unregisterObject(pseudoOutput)
                        followMode.unregisterObject(pseudoOutput)
                    }
                    // Free the mirror's allocator slot while it is hidden, so
                    // auto-floated windows can claim the prime front-center
                    // real estate instead of getting pushed to the fringe.
                    onIsVirtualHiddenChanged: {
                        if (isVirtualHidden) {
                            spaceAllocator.unregisterObject(pseudoOutput)
                            followMode.unregisterObject(pseudoOutput)
                        } else {
                            spaceAllocator.registerObject(pseudoOutput)
                            followMode.registerObject(pseudoOutput)
                        }
                    }
                }
                function findPseudoOutputByOutput(output: QtObject): KwinPseudoOutputMirror {
                    // Check the map first — works even when pseudomirror is hidden (parent: null)
                    const mapped = outputMap[output.name]
                    if (mapped) {
                        return mapped
                    }
                    // Fallback: iterate children for non-mapped entries
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

                    // Pseudo-mirror for this window's host output. May be null if
                    // the output has no mirror, and may have parent===null when
                    // the mirror is hidden (e.g. hideVirtualDisplay). Either
                    // case means the window would render into a detached
                    // subtree — we promote it to vr=true so it floats instead.
                    // Read outputMap directly (not findPseudoOutputByOutput)
                    // because the latter walks repeater.children, which feeds
                    // back into this binding and produces a binding loop.
                    readonly property QtObject hostMirror: {
                        const name = kwinAppWindow.client.output ? kwinAppWindow.client.output.name : ""
                        return outputMirrorRepeater.outputMap[name] ?? null
                    }
                    readonly property bool hostOutputHidden:
                        !hostMirror || hostMirror.parent === null

                    function registerForSpaceAllocator() {
                        if (!spaceAllocator) return
                        spaceAllocator.registerObject(kwinAppWindow)
                    }

                    // Place this window in free 3D space via the shared allocator.
                    // Used when the window auto-floats because its host output is
                    // hidden / missing. turnToFace (not KeepRoll) because the
                    // handle may carry arbitrary roll from prior follow-mode
                    // activity, which would otherwise flip spawns upside down.
                    function placeInFreeSpace() {
                        if (!spaceAllocator || !allWindowsGrabHandle) return
                        if (itemSize.width <= 0 || itemSize.height <= 0) return
                        const globalPos = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                        const localPos = allWindowsGrabHandle.mapPositionFromScene(globalPos)
                        kwinAppWindow.position = localPos
                        KwinVrHelpers.turnToFace(kwinAppWindow, spaceAllocator.viewpoint)
                    }

                    // One-way promotion: if this window's host output is not
                    // renderable, flip it into vr-floating. Idempotent — once
                    // client.vr is true the guard short-circuits, so re-showing
                    // the host mirror does NOT snap the window back (per design:
                    // auto-floated windows stay floating). Placement deferred so
                    // the state-machine's parent swap (screen→vr) applies first.
                    function maybeAutoFloat() {
                        if (!kwinAppWindow.client.vr && kwinAppWindow.hostOutputHidden) {
                            kwinAppWindow.client.vr = true
                            Qt.callLater(placeInFreeSpace)
                        }
                    }
                    onHostOutputHiddenChanged: Qt.callLater(kwinAppWindow.maybeAutoFloat)
                    Component.onCompleted: {
                        Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                        Qt.callLater(kwinAppWindow.maybeAutoFloat)
                    }

                    // Programmatic focus (taskbar click, alt+tab, scripts) —
                    // pull a far-off floating window toward the user while
                    // active, restore its prior pose when focus leaves.
                    Connections {
                        target: kwinAppWindow.client
                        function onActiveChanged() {
                            if (kwinAppWindow.client.active) {
                                xrView.pullAppWinForward(kwinAppWindow)
                            } else if (xrView._focusedPullPose
                                       && xrView._focusedPullPose.window === kwinAppWindow) {
                                xrView._restoreFocusedPullPose()
                            }
                        }
                    }

                    states: [
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
                                script: followMode.registerObject(kwinAppWindow)
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

            // Continuous gizmo drag — ray-plane intersection each frame
            Connections {
                target: pickRay
                enabled: xrView.gizmoDragging
                function onSceneTransformChanged() {
                    if (!xrView.transformGizmo) return
                    const hit = KwinVrHelpers.rayPlaneIntersection(
                        pickRay.scenePosition, pickRay.forward,
                        xrView.gizmoDragPlaneCenter, cam.forward)
                    if (hit.valid) {
                        const localPos = allWindowsGrabHandle.mapPositionFromScene(hit.position)
                        xrView.transformGizmo.updateDrag(localPos)
                    }
                }
            }

        }
    }
}
