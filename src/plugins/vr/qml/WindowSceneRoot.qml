/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * WindowSceneRoot — VR-independent scene data + tree.
 *
 * Owns the registry, the interaction manager, and the Node tree of
 * pseudomirrors + window planes. Designed to be importScene'd by 0..N
 * viewports (XrScene, Vr2DViewport, future remote viewer).
 *
 * What lives here:
 *   - PlaneRegistry: source of truth for which planes exist
 *   - PlaneInteractionManager: single global grab state
 *   - Repeater3D for output mirrors + Repeater3D for app windows
 *   - SelectionPrism visualization (state driven by viewport input)
 *
 * What does NOT live here (per-viewport):
 *   - Camera (XrCamera vs PerspectiveCamera+orbit)
 *   - Input system (pickRay vs MouseArea)
 *   - HUD overlays (head-locked → only XrScene)
 *   - SpaceAllocator3D + VrFollowMode (camera-bound; viewport-supplied)
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    // === Config (scene-level) ===
    property real ppu: KWinVRConfig.ppu
    property real distance: KWinVRConfig.distance

    // === Viewport couplings ===
    // Set by the active viewport. Null when no viewport is wired (e.g. while
    // viewports rotate). Delegates null-check before use.
    property var viewpoint: null         // current "primary" camera (XR or 2D)
    property var spaceAllocator: null    // SpaceAllocator3D for new-window placement
    property var followMode: null        // VrFollowMode for head-tracked window groups
    property var autoAlignTimer: null    // viewport's reset timer (XR only today)
    property var focusControl: null      // VrFocusControl — wired by viewport that owns input
    property string virtualScreenName: ""// suppresses the viewport's own virtual mirror in the scene

    // Whether the world follows the viewpoint. Toggled by viewport UI;
    // currently only XR uses it.
    property bool followCamera: false
    onFollowCameraChanged: followCamera && viewpoint
                           ? (allWindows.position = viewpoint.scenePosition)
                           : null

    // === Selection prism state (driven by viewport input) ===
    property bool prismActive: false
    property vector3d prismAnchor1: Qt.vector3d(0, 0, 0)
    property vector3d prismAnchor2: Qt.vector3d(0, 0, 0)

    // === Public handles ===
    readonly property alias planeRegistry: planeRegistryInstance
    readonly property alias planeInteraction: planeInteractionInstance
    readonly property alias windowDataModel: applicationWindowsRepeater.windowDataModel
    readonly property alias grabHandle: allWindowsGrabHandle
    readonly property alias outputMirrorRepeater: outputMirrorRepeater
    readonly property alias applicationWindowsRepeater: applicationWindowsRepeater

    PlaneRegistry {
        id: planeRegistryInstance
    }

    PlaneInteractionManager {
        id: planeInteractionInstance
        registry: planeRegistryInstance
        topLevelHost: allWindowsGrabHandle
        // xray, picking — set by the active viewport
    }

    // === Reset helper ===
    // Recenters the world on the viewpoint. Viewport-agnostic; viewports may
    // wrap with their own pose-capture rules.
    function resetView() {
        if (!viewpoint) return
        allWindows.position = viewpoint.scenePosition
        const targetPos = viewpoint.mapPositionToScene(Qt.vector3d(0, 0, -root.distance))
        KwinVrHelpers.setNodePositionFromScene(allWindowsGrabHandle, targetPos)
        KwinVrHelpers.setNodeRotationFromScene(allWindowsGrabHandle, viewpoint.sceneRotation)
    }

    // === Selection prism gesture (driven by viewport) ===
    function prismBegin(scenePos) {
        prismAnchor1 = scenePos
        prismAnchor2 = scenePos
        prismActive = true
    }

    function prismUpdate(scenePos) {
        if (!prismActive) return
        prismAnchor2 = scenePos
    }

    // Returns true iff a prism was committed (motion exceeded threshold).
    function prismCommit() {
        if (!prismActive) return false
        const a1 = prismAnchor1
        const a2 = prismAnchor2
        prismActive = false
        const motion = a1.minus(a2).length()
        const threshold = KWinVRConfig.prismMotionThreshold || 0.05
        if (motion < threshold) return false

        const xmin = Math.min(a1.x, a2.x), xmax = Math.max(a1.x, a2.x)
        const ymin = Math.min(a1.y, a2.y), ymax = Math.max(a1.y, a2.y)
        const zmin = Math.min(a1.z, a2.z) - 0.5, zmax = Math.max(a1.z, a2.z) + 0.5
        const captured = []
        const planes = planeRegistryInstance.topLevelPlanes()
        for (const plane of planes) {
            if (!plane.content) continue
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
        const cont = planeInteractionInstance._createContainer(
            CurvedPlane.Mode.Free, centre, Qt.quaternion(1, 0, 0, 0))
        if (!cont) return false
        for (const p of captured) {
            const offset = p.scenePosition.minus(centre)
            cont.addChild(p.planeId, { position: offset })
        }
        return true
    }

    function prismCancel() {
        prismActive = false
    }

    // === Scene tree ===
    Node {
        id: allWindows
        property real ppu: root.ppu

        Connections {
            target: root.viewpoint
            enabled: root.followCamera && root.viewpoint
            function onScenePositionChanged() {
                allWindows.position = root.viewpoint.scenePosition
            }
        }

        Node {
            id: allWindowsGrabHandle
            position: Qt.vector3d(0, 0, -root.distance)

            SelectionPrism {
                active: root.prismActive
                anchor1: root.prismActive
                          ? allWindowsGrabHandle.mapPositionFromScene(root.prismAnchor1)
                          : Qt.vector3d(0, 0, 0)
                anchor2: root.prismActive
                          ? allWindowsGrabHandle.mapPositionFromScene(root.prismAnchor2)
                          : Qt.vector3d(0, 0, 0)
            }

            Repeater3D {
                id: outputMirrorRepeater
                // Map of output → pseudomirror, survives parent:null hiding
                property var outputMap: ({})
                model: OutputModel {}
                delegate: KwinPseudoOutputMirror {
                    id: pseudoOutput
                    readonly property bool isVirtualHidden: root.virtualScreenName.length > 0
                                                           && output.name === ("Virtual-" + root.virtualScreenName)
                                                           && KWinVRConfig.hideVirtualDisplay
                    parent: isVirtualHidden ? null : outputMirrorRepeater
                    ppu: allWindows.ppu
                    registry: planeRegistryInstance
                    topLevelHost: outputMirrorRepeater
                    Component.onCompleted: {
                        outputMirrorRepeater.outputMap[output.name] = pseudoOutput
                        if (root.spaceAllocator && root.spaceAllocator.viewpoint) {
                            const globalPosition = root.spaceAllocator.findFreePosition(itemSize.width, itemSize.height)
                            pseudoOutput.intrinsicPosition = outputMirrorRepeater.mapPositionFromScene(globalPosition)
                            KwinVrHelpers.turnToFaceKeepRoll(pseudoOutput, root.spaceAllocator.viewpoint)
                            pseudoOutput.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                                outputMirrorRepeater.sceneRotation, pseudoOutput.sceneRotation)
                            root.spaceAllocator.registerObject(pseudoOutput)
                        }
                        if (root.followMode) {
                            root.followMode.registerObject(pseudoOutput)
                        }
                    }
                    Component.onDestruction: {
                        delete outputMirrorRepeater.outputMap[output.name]
                    }
                }
                function findPseudoOutputByOutput(output: QtObject): KwinPseudoOutputMirror {
                    const mapped = outputMap[output.name]
                    if (mapped) {
                        return mapped
                    }
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

                    parent: allWindowsGrabHandle
                    registry: planeRegistryInstance
                    topLevelHost: allWindowsGrabHandle

                    client: window
                    windowDataModel: applicationWindowsRepeater.windowDataModel
                    ppu: allWindows.ppu
                    focusControl: root.focusControl

                    function registerForSpaceAllocator() {
                        if (root.spaceAllocator) {
                            root.spaceAllocator.registerObject(kwinAppWindow)
                        }
                    }

                    Component.onCompleted: {
                        Qt.callLater(kwinAppWindow.registerForSpaceAllocator)
                        if (client.vr && root.followMode) {
                            root.followMode.registerObject(kwinAppWindow)
                        }
                    }

                    Connections {
                        target: kwinAppWindow.client
                        function onVrChanged() {
                            if (!root.followMode) return
                            if (kwinAppWindow.client.vr) {
                                root.followMode.registerObject(kwinAppWindow)
                            } else {
                                root.followMode.unregisterObject(kwinAppWindow)
                            }
                        }
                    }
                }
            }
        }
    }
}
