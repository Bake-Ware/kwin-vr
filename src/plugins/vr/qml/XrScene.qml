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

            /* Draw OSD windows in front of user */
            VrOsdWindows {
                windowModel: applicationWindowsRepeater.windowDataModel
                ppu: xrView.ppu
                position: Qt.vector3d(0, 5, -(xrView.distance - 20))
            }

            /* HUD surface — grid + debug snap to this plane */
            Loader3D {
                active: KWinVRConfig.hudEnabled || KWinVRConfig.debugDisplayEnabled
                sourceComponent: VrHudPlane {
                    ppu: xrView.ppu
                    displayWidth: KWinVRConfig.width * KWinVRConfig.scale
                    displayHeight: KWinVRConfig.height * KWinVRConfig.scale
                    lastPick: focusTracking.lastPick
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
                    readonly property bool isVirtualHidden: output.name === ("Virtual-" + kvs.params.name) && KWinVRConfig.hideVirtualDisplay
                    // Remove from scene graph entirely when hidden
                    parent: isVirtualHidden ? null : outputMirrorRepeater
                    ppu: allWindows.ppu
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
                        spaceAllocator.registerObject(kwinAppWindow)
                    }
                    Component.onCompleted: Qt.callLater(kwinAppWindow.registerForSpaceAllocator)

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
