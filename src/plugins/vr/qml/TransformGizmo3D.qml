/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

/*
 * 3D transform gizmo — split into three widget groups pinned to the object.
 *
 *   [Move]        [Rotate]       [Scale]
 *   bottom-left   bottom-center  bottom-right
 *
 * Parented directly to the selected node so it rotates/moves with it.
 * Rotation snaps to 5-degree increments.
 */
Node {
    id: root

    property Node targetNode: null

    // Target context — affects which handles are shown and behavior
    property bool isWindow: false        // use resize instead of scale
    property bool isFlatGeometry: false  // hide Z axis handles

    // Layout — offset below the object, spread horizontally
    property real groupOffsetY: -30
    property real groupSpacing: 22
    // Push gizmos toward camera so they don't clip into geometry
    property real groupOffsetZ: 10

    // Handle rendering
    readonly property real handleDepthBias: -200

    // Move sizing
    property real arrowLength: 15
    property real arrowThickness: 0.6
    property real coneSize: 2.5

    // Rotation wheel sizing
    property real wheelRadius: 8
    property real wheelThickness: 0.4

    // Scale sizing
    property real scaleHandleSize: 3
    property real scaleHandleOffset: 8

    // Axis colors
    readonly property color xColor: "#e74c3c"
    readonly property color yColor: "#2ecc71"
    readonly property color zColor: "#3498db"
    readonly property color xHover: "#ff6b5b"
    readonly property color yHover: "#5dff9e"
    readonly property color zHover: "#5dade2"

    // Interaction state
    property string activeHandle: ""
    property vector3d dragStartPos: Qt.vector3d(0, 0, 0)
    property vector3d targetStartPos: Qt.vector3d(0, 0, 0)
    property quaternion targetStartRot: Qt.quaternion(1, 0, 0, 0)
    property vector3d targetStartScale: Qt.vector3d(1, 1, 1)
    property real rotationSnapDeg: 5

    // Target bounds — positions handles at object edges
    property size targetSize: targetNode && targetNode.itemSize ? targetNode.itemSize : Qt.size(40, 30)
    readonly property real halfW: targetSize.width / 2 * (targetNode ? targetNode.scale.x : 1)
    readonly property real halfH: targetSize.height / 2 * (targetNode ? targetNode.scale.y : 1)
    property real gizmoMargin: 3

    // Counter-scale: gizmo stays constant size regardless of parent scaling
    scale: targetNode ? Qt.vector3d(1/targetNode.scale.x, 1/targetNode.scale.y, 1/targetNode.scale.z) : Qt.vector3d(1,1,1)

    // Signal for window resize (emitted instead of scale when isWindow is true)
    signal windowResizeRequested(real dw, real dh)

    // ========================================================================
    // MOVE — bottom left: translation arrows
    // ========================================================================
    Node {
        id: moveGroup
        position: Qt.vector3d(-root.halfW - root.gizmoMargin, -root.halfH - root.gizmoMargin, root.groupOffsetZ)

        // X axis (red)
        Node {
            eulerRotation.z: -90
            Model {
                source: "#Cylinder"
                scale: Qt.vector3d(root.arrowThickness / 100, root.arrowLength / 200, root.arrowThickness / 100)
                position: Qt.vector3d(0, root.arrowLength / 4, 0)
                pickable: true; depthBias: root.handleDepthBias
                property string handleId: "translateX"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateX" ? root.xHover : root.xColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cone"
                scale: Qt.vector3d(root.coneSize / 100, root.coneSize / 50, root.coneSize / 100)
                position: Qt.vector3d(0, root.arrowLength / 2, 0)
                pickable: true; depthBias: root.handleDepthBias
                property string handleId: "translateX"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateX" ? root.xHover : root.xColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
        }
        // Y axis (green)
        Node {
            Model {
                source: "#Cylinder"
                scale: Qt.vector3d(root.arrowThickness / 100, root.arrowLength / 200, root.arrowThickness / 100)
                position: Qt.vector3d(0, root.arrowLength / 4, 0)
                pickable: true; depthBias: root.handleDepthBias
                property string handleId: "translateY"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateY" ? root.yHover : root.yColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cone"
                scale: Qt.vector3d(root.coneSize / 100, root.coneSize / 50, root.coneSize / 100)
                position: Qt.vector3d(0, root.arrowLength / 2, 0)
                pickable: true; depthBias: root.handleDepthBias
                property string handleId: "translateY"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateY" ? root.yHover : root.yColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
        }
        // Z axis (blue) — hidden for flat geometry
        Node {
            visible: !root.isFlatGeometry
            eulerRotation.x: 90
            Model {
                source: "#Cylinder"
                scale: Qt.vector3d(root.arrowThickness / 100, root.arrowLength / 200, root.arrowThickness / 100)
                position: Qt.vector3d(0, root.arrowLength / 4, 0)
                pickable: !root.isFlatGeometry; depthBias: root.handleDepthBias
                property string handleId: "translateZ"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateZ" ? root.zHover : root.zColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            Model {
                source: "#Cone"
                scale: Qt.vector3d(root.coneSize / 100, root.coneSize / 50, root.coneSize / 100)
                position: Qt.vector3d(0, root.arrowLength / 2, 0)
                pickable: !root.isFlatGeometry; depthBias: root.handleDepthBias
                property string handleId: "translateZ"
                materials: PrincipledMaterial {
                    baseColor: root.activeHandle === "translateZ" ? root.zHover : root.zColor
                    lighting: PrincipledMaterial.NoLighting
                }
            }
        }
    }

    // ========================================================================
    // ROTATE — bottom center: three wheel disks
    // ========================================================================
    // X rotation wheel (red) — center-left of object
    Model {
        source: "#Cylinder"
        eulerRotation.z: 90
        scale: Qt.vector3d(root.wheelRadius / 50, root.wheelThickness / 50, root.wheelRadius / 50)
        position: Qt.vector3d(-root.halfW - root.wheelRadius - root.gizmoMargin, 0, root.groupOffsetZ)
        pickable: true; depthBias: root.handleDepthBias
        property string handleId: "rotateX"
        materials: PrincipledMaterial {
            baseColor: root.activeHandle === "rotateX" ? root.xHover : root.xColor
            alphaMode: PrincipledMaterial.Blend; opacity: 0.7
            lighting: PrincipledMaterial.NoLighting
        }
    }
    // Y rotation wheel (green) — center-bottom of object
    Model {
        source: "#Cylinder"
        scale: Qt.vector3d(root.wheelRadius / 50, root.wheelThickness / 50, root.wheelRadius / 50)
        position: Qt.vector3d(0, -root.halfH - root.wheelRadius - root.gizmoMargin, root.groupOffsetZ)
        pickable: true; depthBias: root.handleDepthBias
        property string handleId: "rotateY"
        materials: PrincipledMaterial {
            baseColor: root.activeHandle === "rotateY" ? root.yHover : root.yColor
            alphaMode: PrincipledMaterial.Blend; opacity: 0.7
            lighting: PrincipledMaterial.NoLighting
        }
    }
    // Z rotation wheel (blue) — center of object
    Model {
        source: "#Cylinder"
        eulerRotation.x: 90
        scale: Qt.vector3d(root.wheelRadius / 50, root.wheelThickness / 50, root.wheelRadius / 50)
        position: Qt.vector3d(0, 0, root.groupOffsetZ)
        pickable: true; depthBias: root.handleDepthBias
        property string handleId: "rotateZ"
            materials: PrincipledMaterial {
                baseColor: root.activeHandle === "rotateZ" ? root.zHover : root.zColor
                alphaMode: PrincipledMaterial.Blend; opacity: 0.7
                lighting: PrincipledMaterial.NoLighting
            }
        }

    // ========================================================================
    // SCALE — bottom right: axis cubes + uniform center cube
    // ========================================================================
    Node {
        id: scaleGroup
        position: Qt.vector3d(root.halfW + root.gizmoMargin, -root.halfH - root.gizmoMargin, root.groupOffsetZ)

        // X scale (red)
        Model {
            source: "#Cube"
            position: Qt.vector3d(root.scaleHandleOffset, 0, 0)
            scale: Qt.vector3d(root.scaleHandleSize / 100, root.scaleHandleSize / 100, root.scaleHandleSize / 100)
            pickable: true; depthBias: root.handleDepthBias
            property string handleId: "scaleX"
            materials: PrincipledMaterial {
                baseColor: root.activeHandle === "scaleX" ? root.xHover : root.xColor
                lighting: PrincipledMaterial.NoLighting
            }
        }
        // Y scale (green)
        Model {
            source: "#Cube"
            position: Qt.vector3d(0, root.scaleHandleOffset, 0)
            scale: Qt.vector3d(root.scaleHandleSize / 100, root.scaleHandleSize / 100, root.scaleHandleSize / 100)
            pickable: true; depthBias: root.handleDepthBias
            property string handleId: "scaleY"
            materials: PrincipledMaterial {
                baseColor: root.activeHandle === "scaleY" ? root.yHover : root.yColor
                lighting: PrincipledMaterial.NoLighting
            }
        }
        // Z scale (blue) — hidden for flat geometry
        Model {
            visible: !root.isFlatGeometry
            source: "#Cube"
            position: Qt.vector3d(0, 0, root.scaleHandleOffset)
            scale: Qt.vector3d(root.scaleHandleSize / 100, root.scaleHandleSize / 100, root.scaleHandleSize / 100)
            pickable: !root.isFlatGeometry; depthBias: root.handleDepthBias
            property string handleId: "scaleZ"
            materials: PrincipledMaterial {
                baseColor: root.activeHandle === "scaleZ" ? root.zHover : root.zColor
                lighting: PrincipledMaterial.NoLighting
            }
        }
        // Uniform scale (center)
        Model {
            source: "#Cube"
            scale: Qt.vector3d(root.scaleHandleSize * 1.3 / 100, root.scaleHandleSize * 1.3 / 100, root.scaleHandleSize * 1.3 / 100)
            pickable: true; depthBias: root.handleDepthBias
            property string handleId: "scaleUniform"
            materials: PrincipledMaterial {
                baseColor: root.activeHandle === "scaleUniform" ? "#ffff00" : "#cccccc"
                lighting: PrincipledMaterial.NoLighting
            }
        }
    }

    // ========================================================================
    // CONFIRM — top center: click to close gizmo mode
    // ========================================================================
    Model {
        source: "#Cube"
        position: Qt.vector3d(0, root.halfH + root.gizmoMargin + root.scaleHandleSize, root.groupOffsetZ)
        scale: Qt.vector3d(root.scaleHandleSize * 1.5 / 100, root.scaleHandleSize * 1.5 / 100, root.scaleHandleSize * 1.5 / 100)
        pickable: true; depthBias: root.handleDepthBias
        property string handleId: "confirmGizmo"
        materials: PrincipledMaterial {
            baseColor: "#27ae60"
            lighting: PrincipledMaterial.NoLighting
        }
    }

    // ========================================================================
    // Interaction
    // ========================================================================

    function isGizmoHandle(obj) {
        return obj && obj.handleId !== undefined
    }

    function beginDrag(handleId, rayPos) {
        root.activeHandle = handleId
        root.dragStartPos = rayPos
        if (root.targetNode) {
            root.targetStartPos = root.targetNode.position
            root.targetStartRot = root.targetNode.rotation
            root.targetStartScale = root.targetNode.scale
        }
    }

    function updateDrag(rayPos) {
        if (!root.activeHandle || !root.targetNode) return

        const delta = rayPos.minus(root.dragStartPos)

        if (root.activeHandle.startsWith("translate")) {
            // Transform local axis to parent space so movement follows the gizmo arrows
            let localAxis = Qt.vector3d(0, 0, 0)
            if (root.activeHandle === "translateX") localAxis = Qt.vector3d(1, 0, 0)
            else if (root.activeHandle === "translateY") localAxis = Qt.vector3d(0, 1, 0)
            else if (root.activeHandle === "translateZ") localAxis = Qt.vector3d(0, 0, 1)
            const parentAxis = KwinVrHelpers.rotateVector(root.targetStartRot, localAxis)
            const moveVec = parentAxis.times(delta.dotProduct(parentAxis))
            root.targetNode.position = root.targetStartPos.plus(moveVec)

        } else if (root.activeHandle.startsWith("rotate")) {
            // Transform local axis to parent space so rotation follows the gizmo wheels
            let localAxis = Qt.vector3d(0, 0, 0)
            if (root.activeHandle === "rotateX") localAxis = Qt.vector3d(1, 0, 0)
            else if (root.activeHandle === "rotateY") localAxis = Qt.vector3d(0, 1, 0)
            else if (root.activeHandle === "rotateZ") localAxis = Qt.vector3d(0, 0, 1)
            const axis = KwinVrHelpers.rotateVector(root.targetStartRot, localAxis)

            // Linear rotation: perpendicular drag distance → degrees
            const rotationSensitivity = 1.0
            const perpDelta = delta.minus(axis.times(delta.dotProduct(axis)))
            const refVec = root.dragStartPos.minus(root.targetStartPos)
            const refPerp = refVec.minus(axis.times(refVec.dotProduct(axis)))
            const crossDir = axis.crossProduct(refPerp.length() > 0.001 ? refPerp.normalized() : Qt.vector3d(1, 0, 0))
            const sign = perpDelta.dotProduct(crossDir) >= 0 ? 1 : -1
            let angleDeg = sign * perpDelta.length() * rotationSensitivity

            angleDeg = Math.round(angleDeg / root.rotationSnapDeg) * root.rotationSnapDeg

            if (angleDeg !== 0) {
                const angleRad = angleDeg * Math.PI / 180
                const half = angleRad / 2
                const s = Math.sin(half)
                const deltaQ = Qt.quaternion(Math.cos(half), axis.x * s, axis.y * s, axis.z * s)
                root.targetNode.rotation = KwinVrHelpers.multiplyQuaternions(deltaQ, root.targetStartRot)
            }

        } else if (root.activeHandle.startsWith("scale")) {
            const sensitivity = root.isWindow ? 5.0 : 0.02
            let scaleDelta = delta.length() * sensitivity
            if (delta.x + delta.y + delta.z < 0) scaleDelta = -scaleDelta

            if (root.isWindow) {
                // Windows: resize (pixels) instead of scale
                let dw = 0, dh = 0
                if (root.activeHandle === "scaleX") dw = scaleDelta
                else if (root.activeHandle === "scaleY") dh = scaleDelta
                else if (root.activeHandle === "scaleUniform") { dw = scaleDelta; dh = scaleDelta }
                root.windowResizeRequested(dw, dh)
            } else {
                if (root.activeHandle === "scaleX") {
                    root.targetNode.scale = Qt.vector3d(
                        Math.max(0.1, root.targetStartScale.x + scaleDelta),
                        root.targetStartScale.y, root.targetStartScale.z)
                } else if (root.activeHandle === "scaleY") {
                    root.targetNode.scale = Qt.vector3d(
                        root.targetStartScale.x,
                        Math.max(0.1, root.targetStartScale.y + scaleDelta),
                        root.targetStartScale.z)
                } else if (root.activeHandle === "scaleZ") {
                    root.targetNode.scale = Qt.vector3d(
                        root.targetStartScale.x, root.targetStartScale.y,
                        Math.max(0.1, root.targetStartScale.z + scaleDelta))
                } else if (root.activeHandle === "scaleUniform") {
                    const s = Math.max(0.1, 1.0 + scaleDelta)
                    root.targetNode.scale = Qt.vector3d(
                        root.targetStartScale.x * s,
                        root.targetStartScale.y * s,
                        root.targetStartScale.z * s)
                }
            }
        }
    }

    function endDrag() {
        root.activeHandle = ""
    }
}
