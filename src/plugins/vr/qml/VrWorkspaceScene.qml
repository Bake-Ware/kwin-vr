/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin as KWinC
import org.kde.kwin.vr

/*
 * The renderer-agnostic 3D workspace: windows, pseudomirrors, picking ray,
 * HUD, radial menu, snap manager — everything except the view/session itself.
 *
 * This is the M2 "renderer seam": scene roots (XrScene for OpenXR, FlatScene
 * for a plain monitor) instantiate this component, hand it a camera and a
 * picking view, and expose it as `workspace`. Code below this node must never
 * import QtQuick3D.Xr (enforced by ci/check-xr-imports.sh).
 */
Node {
    id: root

    /* The active head/eye camera (XrCamera or PerspectiveCamera). */
    required property Node camera
    /* Object providing rayPickAll(pos, dir) — XrView and View3D both do. */
    required property QtObject pickingView
    property KwinVrInputDevice kwinInput
    property KwinVrInputFilter kwinInputFilter

    property real ppu: KWinVRConfig.ppu
    property real distance: KWinVRConfig.distance

    /* Blend/passthrough is a scene-root capability (XR passthrough); the
       radial menu requests it, the scene root implements it. */
    property bool blendEnabled: false
    property bool blendSupported: false
    signal blendToggleRequested()

    property alias hudEnabled: hudLoader.active
    property alias rayEnabled: pickRay.enabled
    property alias cursorEnabled: focusTracking.cursorEnabled
    property alias grabbed: pickRay.grabbedObject
    readonly property bool worldGrabbed: pickRay.grabbedObject === allWindowsGrabHandle
    readonly property var cursorHoverObject: focusTracking.cursorHoverObject
    property alias currentMovingResizingWindow: focusTracking.currentMovingResizingWindow
    property alias pullGrabbed: pickRay.pullGrabbed
    property alias pushGrabbed: pickRay.pushGrabbed
    property alias headScroll: headScroll
    property alias desktopOrDockHovered: focusTracking.desktopOrDockHovered

    /* Introspection for the replay harness (evalInWorkspace test hook):
       read-only window/mirror access, no behavior. */
    readonly property alias appWindows: applicationWindowsRepeater
    readonly property alias outputMirrors: outputMirrorRepeater
    readonly property alias snap: snapManager
    readonly property alias allocator: spaceAllocator
    readonly property alias hudWindows: hudWindowsRepeater

    property bool test1: false
    onTest1Changed: {
        KwinVrHelpers.activateOutput(kvs.output, KWinVRConfig.scale)
    }

    function die() {  }
    function resetView() { allWindows.resetView() }

    /* -------- focus pull (#26 follow-up, VOC-FOCUS-010/020) --------
       On window activation (taskbar, alt+tab, scripts) a far-off vr-floating
       window slides along its cam→window ray to the sibling-average depth and
       faces the user; followMode pans the world so it ends up centered. On
       defocus the window's prior pose is restored. */

    // Saved scene pose of the focused window; null when no pull is active.
    property var _focusedPullPose: null

    function _restoreFocusedPullPose() {
        if (!_focusedPullPose)
            return
        const pose = _focusedPullPose
        _focusedPullPose = null
        // Cancel any in-flight pan first — restoring the pose moves the
        // window away mid-pan, and a live override would drag the world
        // right back after it.
        followMode.unfocus(pose.window)
        if (pose.window && pose.window.client && pose.window.client.vr) {
            KwinVrHelpers.setNodePositionFromScene(pose.window, pose.position)
            KwinVrHelpers.setNodeRotationFromScene(pose.window, pose.rotation)
        }
    }

    // Average distance from camera to every vr-floating window, excluding
    // the target. Used as the depth target for the focus pull.
    function _averageFloatingDistance(exclude) {
        const camPos = root.camera.scenePosition
        let total = 0.0
        let count = 0
        for (let i = 0; i < applicationWindowsRepeater.count; ++i) {
            const w = applicationWindowsRepeater.objectAt(i)
            if (!w || w === exclude) continue
            if (!w.client || !w.client.vr || !w.visible) continue
            if (w.stackedOnto) continue
            total += w.scenePosition.minus(camPos).length()
            count += 1
        }
        return count === 0 ? root.distance : total / count
    }

    // True if `w` participates in a dock/stack — those windows' poses belong
    // to the snap manager, not the focus pull.
    function _isSnapInvolved(w) {
        if (w.stackedOnto)
            return true
        for (let i = 0; i < applicationWindowsRepeater.count; ++i) {
            const other = applicationWindowsRepeater.objectAt(i)
            if (other && other !== w && other.stackedOnto === w)
                return true
        }
        return false
    }

    // Focus pull: slide the window along its cam→window direction to the
    // sibling-average depth and re-face it to the user. Angular position in
    // the user's surroundings is preserved (no teleport to center) — the
    // world pan (followMode.focusOn) brings it the rest of the way.
    function pullAppWinForward(appWin) {
        if (!appWin || !appWin.client || !appWin.client.vr)
            return
        if (_isSnapInvolved(appWin))
            return
        if (_focusedPullPose && _focusedPullPose.window === appWin)
            return
        _restoreFocusedPullPose()

        const camPos = root.camera.scenePosition
        const windowPos = appWin.scenePosition
        let dir = windowPos.minus(camPos)
        const currentDist = dir.length()
        if (currentDist < 0.0001)
            return
        dir = dir.times(1.0 / currentDist)

        // Deep-copy the pose: scenePosition/sceneRotation are QML value-type
        // *references* — stored raw they'd track the window through the pull
        // and pan, making the restore a no-op.
        const sceneRot = appWin.sceneRotation
        _focusedPullPose = {
            window: appWin,
            position: Qt.vector3d(windowPos.x, windowPos.y, windowPos.z),
            rotation: Qt.quaternion(sceneRot.scalar, sceneRot.x, sceneRot.y, sceneRot.z)
        }

        const newPos = camPos.plus(dir.times(_averageFloatingDistance(appWin)))
        KwinVrHelpers.setNodePositionFromScene(appWin, newPos)
        KwinVrHelpers.turnToFace(appWin, root.camera)

        // Pan the world so the focused window ends up centered. Passes the
        // camera explicitly because followMode.camera is null-gated during
        // hover/grab/menu. No-op if already within the reactive FOV.
        followMode.focusOn(appWin, root.camera)
    }

    // If the user grabs the focus-pulled window, grab becomes authoritative:
    // drop the saved pose so defocus doesn't snap it back behind them.
    Connections {
        target: pickRay
        function onGrabbedObjectChanged() {
            if (root._focusedPullPose
                && pickRay.grabbedObject === root._focusedPullPose.window) {
                // The grab is authoritative over the pan too.
                followMode.unfocus(root._focusedPullPose.window)
                root._focusedPullPose = null
            }
        }
    }

    Timer {
        id: autoAlignTimer
        onTriggered: allWindows.resetView()
        interval: KWinVRConfig.resetViewDelay * 1000
    }
    Component.onCompleted: {
        if(KWinVRConfig.resetViewDelay >= 0)
            autoAlignTimer.start()
    }

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

    RelativeMotionBlocker {
        allowedDevice: root.kwinInput
    }

    VrPointerOffset {
        id: pointerOffset
        enabled: !KWinVRConfig.blockOtherPointerMotion
        vrDevice: root.kwinInput
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
        target: root.camera
        enabled: KWinVRConfig.gazeReclaimEnabled && pointerOffset.enabled
                 && (pointerOffset.offsetX !== 0 || pointerOffset.offsetY !== 0)
        function onSceneRotationChanged() {
            if (!gazeReclaim.hasReference) {
                gazeReclaim.referenceRotation = root.camera.sceneRotation
                gazeReclaim.hasReference = true
                return
            }
            const delta = KwinVrHelpers.getRotationDelta(gazeReclaim.referenceRotation, root.camera.sceneRotation)
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
                gazeReclaim.referenceRotation = root.camera.sceneRotation
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
            KwinVrHelpers.turnToFaceKeepRoll(hobj, root.camera)
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

    VrHeadScroll {
        id: headScroll
        camera: root.camera
        verticalScrollMultiplier: KWinVRConfig.verticalHeadScrollSpeed
        horizontalScrollMultiplier: KWinVRConfig.horizontalHeadScrollSpeed
        threshold: KWinVRConfig.headScrollThreshold
    }

    VrFocusControl {
        id: focusTracking
        headScroll: headScroll
        kwinInput: root.kwinInput
        kwinInputFilter: root.kwinInputFilter
        cursor3d: vrCursor
        xray: pickRay
        xrView: root.pickingView
    }

    // #14 step 1 — quad-overlap snap intent detection. Log only, no visual.
    WindowSnapManager {
        id: snapManager
        xray: pickRay
        windowsRepeater: applicationWindowsRepeater
        picking: focusTracking.picking
        kwinInput: root.kwinInput
    }

    VrKwinCursor {
        id: vrCursor
        ppu: root.ppu
        visible: false
    }

    /* Camera-attached content: HUD surface and the picking ray follow the
       head. Reparented into whatever camera the scene root provides. */
    Node {
        id: cameraRig
        parent: root.camera

        DirectionalLight {}

        /* HUD surface — grid + debug + overlay windows */
        Node {
            id: hudNode

            readonly property int dw: KWinVRConfig.width * KWinVRConfig.scale
            readonly property int dh: KWinVRConfig.height * KWinVRConfig.scale
            readonly property real surfaceW: dw / root.ppu * KWinVRConfig.hudScaleH
            readonly property real surfaceH: dh / root.ppu * KWinVRConfig.hudScaleV
            readonly property real hudDistance: KWinVRConfig.distance * KWinVRConfig.hudDistanceFraction / 100.0
            readonly property real hudY: -(hudDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))

            position: Qt.vector3d(0, hudY, -hudDistance)

            /* Grid + debug overlay (only when enabled) */
            Loader3D {
                active: KWinVRConfig.hudEnabled || KWinVRConfig.debugDisplayEnabled
                sourceComponent: VrHudPlane {
                    ppu: root.ppu
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
                    ppu: root.ppu
                    hudSurfaceW: hudNode.surfaceW
                    hudSurfaceH: hudNode.surfaceH
                    hudCurvature: KWinVRConfig.hudCurvature
                }
            }
        }

        Xray {
            id: pickRay
            camera: root.camera
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
                    ppu: root.ppu
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
                position = pickRay.mapPositionToNode(parent, Qt.vector3d(0,0, -(root.distance - 20)))
                rotation = KwinVrHelpers.targetSceneRotationToNodeRotation(this, root.camera)
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
                root.blendEnabled
            ]
            onButtonClicked: (index) => {
                                 if(index === 0) {
                                     pickRay.enabled = false
                                     radialMenuLoader.active = false
                                 } else if(index === 1) {
                                     allWindows.resetView()
                                     radialMenuLoader.active = false
                                 } else if (index === 2) {
                                     root.grab(true)
                                     radialMenuLoader.active = false
                                 } else if (index === 3) {
                                     allWindows.followCamera = !allWindows.followCamera
                                 }  else if (index === 4) {
                                     root.blendToggleRequested()
                                 }
                             }
        }
    }

    Node {
        id: allWindows
        property real ppu: root.ppu
        property bool followCamera: false
        Component.onCompleted: followCamera = KWinVRConfig.followEnabled
        onFollowCameraChanged: followCamera ? (allWindows.position = root.camera.scenePosition) : null

        function resetView() {
            allWindows.position = root.camera.scenePosition
            const targetPos = root.camera.mapPositionToScene(Qt.vector3d(0, 0, -root.distance))
            KwinVrHelpers.setNodePositionFromScene(allWindowsGrabHandle, targetPos)
            // Maybe to respect followMode's followWorldUpAlignment ?
            KwinVrHelpers.setNodeRotationFromScene(allWindowsGrabHandle, root.camera.sceneRotation)
        }

        Connections {
            target: root.camera
            enabled: allWindows.followCamera
            function onScenePositionChanged() {
                allWindows.position = root.camera.scenePosition
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

                return root.camera
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
            position: Qt.vector3d(0, 0, -root.distance)

            SpaceAllocator3D {
                id: spaceAllocator
                viewpoint: root.camera
                distance: root.distance
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
                    parent: null
                    client: window
                    windowDataModel: applicationWindowsRepeater.windowDataModel
                    ppu: allWindows.ppu
                    focusControl: focusTracking
                    property real zOffset: 0
                    property int stackingOrder: client.stackingOrder

                    onStackFocusRequested: snapManager.promoteStackMember(kwinAppWindow)

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

                    // Pseudomirror for this window's host output. May be null if
                    // the output has no mirror, and may have parent===null when
                    // the mirror is hidden (e.g. hideVirtualDisplay). Either case
                    // means the window would render into a detached subtree — we
                    // promote it to vr=true so it floats instead (#26). Read
                    // outputMap directly (not findPseudoOutputByOutput) because
                    // the latter walks repeater.children, which feeds back into
                    // this binding and produces a binding loop.
                    readonly property QtObject hostMirror: {
                        const name = kwinAppWindow.client.output ? kwinAppWindow.client.output.name : ""
                        return outputMirrorRepeater.outputMap[name] ?? null
                    }
                    readonly property bool hostOutputHidden:
                        !hostMirror || hostMirror.parent === null

                    function registerForSpaceAllocator() {
                        spaceAllocator.registerObject(kwinAppWindow)
                    }

                    // Place this window in free 3D space via the shared allocator.
                    // Used when the window auto-floats because its host output is
                    // hidden / missing. turnToFace (not KeepRoll) because the
                    // handle may carry arbitrary roll from prior follow-mode
                    // activity, which would otherwise flip spawns upside down.
                    function placeInFreeSpace() {
                        if (itemSize.width <= 0 || itemSize.height <= 0) {
                            return
                        }
                        const globalPos = spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                        kwinAppWindow.position = allWindowsGrabHandle.mapPositionFromScene(globalPos)
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
                            Qt.callLater(kwinAppWindow.placeInFreeSpace)
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
                                root.pullAppWinForward(kwinAppWindow)
                            } else if (root._focusedPullPose
                                       && root._focusedPullPose.window === kwinAppWindow) {
                                root._restoreFocusedPullPose()
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
        }
    }
}
