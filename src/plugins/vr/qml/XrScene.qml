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
    readonly property bool worldGrabbed: pickRay.grabbedObject === allWindowsGrabHandle
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

    function grabMoveClamped(value: real, minDist: real, maxDist: real): void {
        pickRay.grabMoveClamped(value, minDist, maxDist)
    }

    // Scroll-to-depth for grabbed detached VR windows and the whole-world grab.
    // Each scroll step applies one sensitivity unit in the sign direction.
    function scrollGrab(delta: real): void {
        if (!pickRay.grabbedObject)
            return
        const isWorld = pickRay.grabbedObject === allWindowsGrabHandle
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

    // #14 step 1 — quad-overlap snap intent detection. Log only, no visual.
    WindowSnapManager {
        id: snapManager
        xray: pickRay
        windowsRepeater: applicationWindowsRepeater
        picking: focusTracking.picking
        kwinInput: xrView.kwinInput
    }

    // Single registry of every CurvedPlane in the scene. Reachable via
    // xrView.planeRegistry from any descendant.
    PlaneRegistry {
        id: planeRegistryInstance
    }
    readonly property alias planeRegistry: planeRegistryInstance

    PlaneInteractionManager {
        id: planeInteraction
        xray: pickRay
        picking: focusTracking.picking
        registry: planeRegistryInstance
        topLevelHost: allWindowsGrabHandle
    }

    // Selection prism state — driven by Main.qml's right-click drag gesture.
    property vector3d _prismAnchor1: Qt.vector3d(0, 0, 0)
    property vector3d _prismAnchor2: Qt.vector3d(0, 0, 0)
    property bool _prismActive: false

    function prismBegin() {
        const p = pickRay.scenePosition.plus(pickRay.forward.times(xrView.distance))
        _prismAnchor1 = p
        _prismAnchor2 = p
        _prismActive = true
    }

    function prismUpdate() {
        if (!_prismActive) return
        const p = pickRay.scenePosition.plus(pickRay.forward.times(xrView.distance))
        _prismAnchor2 = p
    }

    // Returns true iff a prism was committed (i.e. motion exceeded threshold
    // and a container was created — radial menu should NOT fire on release).
    function prismCommit() {
        if (!_prismActive) return false
        const a1 = _prismAnchor1
        const a2 = _prismAnchor2
        _prismActive = false
        const motion = a1.minus(a2).length()
        const threshold = KWinVRConfig.prismMotionThreshold || 0.05
        if (motion < threshold) return false

        const xmin = Math.min(a1.x, a2.x), xmax = Math.max(a1.x, a2.x)
        const ymin = Math.min(a1.y, a2.y), ymax = Math.max(a1.y, a2.y)
        const zmin = Math.min(a1.z, a2.z) - 0.5, zmax = Math.max(a1.z, a2.z) + 0.5
        const captured = []
        const planes = planeRegistryInstance.topLevelPlanes()
        for (const plane of planes) {
            if (!plane.content) continue   // skip containers, only capture window planes
            if (plane._isPseudomirror) continue
            const sp = plane.scenePosition
            if (sp.x >= xmin && sp.x <= xmax
                && sp.y >= ymin && sp.y <= ymax
                && sp.z >= zmin && sp.z <= zmax) {
                captured.push(plane)
            }
        }
        if (captured.length < 1) return false

        const centre = Qt.vector3d((a1.x + a2.x) / 2,
                                   (a1.y + a2.y) / 2,
                                   (a1.z + a2.z) / 2)
        const cont = planeInteraction._createContainer(
            CurvedPlane.Mode.Free, centre, Qt.quaternion(1, 0, 0, 0))
        if (!cont) return false
        for (const p of captured) {
            const offset = p.scenePosition.minus(centre)
            cont.addChild(p.planeId, { position: offset })
        }
        return true
    }

    function prismCancel() {
        _prismActive = false
    }

    // Alt+wheel curvature nudge on the hovered plane. Always writes the
    // per-window override (intrinsicCurvature when top-level, slot
    // override when abducted) — matches "modify while child writes the
    // override" rule from architecture.
    function curvatureNudge(direction) {
        const obj = focusTracking.hoveredGrabHandle
        const plane = planeInteraction._planeFromObject(obj)
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

            // Selection prism visualisation — wireframe rect between
            // the gesture's anchor points.
            SelectionPrism {
                active: xrView._prismActive
                anchor1: xrView._prismActive
                          ? allWindowsGrabHandle.mapPositionFromScene(xrView._prismAnchor1)
                          : Qt.vector3d(0, 0, 0)
                anchor2: xrView._prismActive
                          ? allWindowsGrabHandle.mapPositionFromScene(xrView._prismAnchor2)
                          : Qt.vector3d(0, 0, 0)
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
                // Map of output → pseudomirror, survives parent:null hiding
                property var outputMap: ({})
                model: OutputModel {}
                delegate: KwinPseudoOutputMirror {
                    id: pseudoOutput
                    readonly property bool isVirtualHidden: output.name === ("Virtual-" + kvs.params.name) && KWinVRConfig.hideVirtualDisplay
                    // Remove from scene graph entirely when hidden
                    parent: isVirtualHidden ? null : outputMirrorRepeater
                    ppu: allWindows.ppu
                    registry: planeRegistryInstance
                    topLevelHost: outputMirrorRepeater
                    Component.onCompleted: {
                        outputMirrorRepeater.outputMap[output.name] = pseudoOutput
                        const globalPosition = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                        // CurvedPlane drives `position` from intrinsicPosition via
                        // a Binding; write the intrinsic so it propagates.
                        pseudoOutput.intrinsicPosition = outputMirrorRepeater.mapPositionFromScene(globalPosition)
                        KwinVrHelpers.turnToFaceKeepRoll(pseudoOutput, spaceAllocator.viewpoint)
                        // turnToFaceKeepRoll wrote `rotation` imperatively; capture
                        // back to intrinsicRotation so the binding stays consistent.
                        pseudoOutput.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                            outputMirrorRepeater.sceneRotation, pseudoOutput.sceneRotation)
                        spaceAllocator.registerObject(pseudoOutput)
                        followMode.registerObject(pseudoOutput)
                    }
                    Component.onDestruction: {
                        delete outputMirrorRepeater.outputMap[output.name]
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

            // #14 step 2 — telegraph ghost. Translucent rect at landing pose.
            // Parented here so target.rotation maps directly (both share parent).
            Model {
                id: telegraphGhost
                source: "#Rectangle"
                visible: snapManager.currentTarget !== null
                         && snapManager.currentAction !== WindowSnapManager.Action.None
                         && snapManager.landingSize.width > 0
                         && snapManager.landingSize.height > 0
                position: snapManager.currentTarget
                          ? allWindowsGrabHandle.mapPositionFromScene(
                                snapManager.currentTarget.mapPositionToScene(
                                    Qt.vector3d(snapManager.landingLocalOffset.x,
                                                snapManager.landingLocalOffset.y,
                                                snapManager.landingLocalOffset.z + KWinVRConfig.zSurfaceMarginTop)))
                          : Qt.vector3d(0, 0, 0)
                rotation: snapManager.currentTarget ? snapManager.currentTarget.rotation : Qt.quaternion(1, 0, 0, 0)
                scale: Qt.vector3d(snapManager.landingSize.width / 100,
                                   snapManager.landingSize.height / 100, 1)
                depthBias: -100
                materials: [
                    DefaultMaterial {
                        diffuseColor: Qt.rgba(0.3, 0.7, 1.0, 1.0)
                        opacity: 0.4
                        lighting: DefaultMaterial.NoLighting
                        cullMode: Material.NoCulling
                        depthDrawMode: Material.OpaqueOnlyDepthDraw
                    }
                ]
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

                    // CurvedPlane lives at the top-level scene-graph host always.
                    // The abductor binding (set when client.vr === false in
                    // KwinApplicationWindow itself) computes screen-state
                    // placement; no Qt reparenting needed.
                    parent: allWindowsGrabHandle
                    registry: planeRegistryInstance
                    topLevelHost: allWindowsGrabHandle

                    client: window
                    windowDataModel: applicationWindowsRepeater.windowDataModel
                    ppu: allWindows.ppu
                    focusControl: focusTracking

                    function registerForSpaceAllocator() {
                        spaceAllocator.registerObject(kwinAppWindow)
                    }

                    Component.onCompleted: {
                        Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                        // VR-state windows participate in followMode; track here.
                        if (client.vr) {
                            followMode.registerObject(kwinAppWindow)
                        }
                    }

                    Connections {
                        target: kwinAppWindow.client
                        function onVrChanged() {
                            if (kwinAppWindow.client.vr) {
                                followMode.registerObject(kwinAppWindow)
                            } else {
                                followMode.unregisterObject(kwinAppWindow)
                            }
                        }
                    }
                }
            }
        }
    }
}
