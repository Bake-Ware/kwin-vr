/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick3D
import QtQuick3D.Helpers

Item {
    id: root
    clip: true  // Prevent scroll events from propagating to parent

    // Position properties (in cm, matching kcfg)
    property real positionX: 15.0
    property real positionY: -10.0
    property real positionZ: -5.0

    // Rotation properties (in degrees)
    property real rotationHorizontal: 4.0
    property real rotationVertical: 6.0

    // Ray color
    property color rayColor: "#cccccc"

    // Scale factor: convert cm to scene units (1 cm = 1 unit for clarity)
    readonly property real sceneScale: 1.0

    // Ray length for visualization
    property real rayLength: hasTarget ? targetPoint.minus(Qt.vector3d(positionX, positionY, positionZ)).length() : 80.0

    // Handle sizes
    readonly property real positionHandleRadius: 4.0
    readonly property real rotationHandleRadius: 3.0 // Unused but kept for compatibility
    readonly property real rotationHandleDistance: 40.0

    // Target tracking
    property real maxRotationAngle: 45.0
    property vector3d targetPoint: Qt.vector3d(0, 0, -100)
    property bool hasTarget: false

    // Flag to prevent feedback loops
    property bool updatingRotation: false
    property bool ready: false

    // Display properties
    property real displayWidth: 60.0
    property real displayHeight: 40.0
    property real displayDistance: 100.0

    // Initialize target from rotation on load and when parameters change
    Component.onCompleted: {
        updateTargetFromRotation()
        root.ready = true
    }
    onRotationHorizontalChanged: updateTargetFromRotation()
    onRotationVerticalChanged: updateTargetFromRotation()
    onDisplayDistanceChanged: updateTargetFromRotation()

    onPositionXChanged: updateRotationToTarget()
    onPositionYChanged: updateRotationToTarget()
    onPositionZChanged: updateRotationToTarget()

    // --- Resources ---

    KdeKubes {
        id: cubes
    }

    Image {
        id: kdeWhite
        visible: false
        source: cubes.logoWhiteBlue
    }

    // --- Helper Functions ---

    function clamp(val: real, min: real, max: real) : real {
        return Math.max(min, Math.min(max, val))
    }

    function getRay(viewX: real, viewY: real) : var {
        // Use mapTo3DScene to get points on near plane and at a distance
        const nearPos = view3d.mapTo3DScene(Qt.vector3d(viewX, viewY, 0))
        const farPos = view3d.mapTo3DScene(Qt.vector3d(viewX, viewY, 100))
        return {
            origin: nearPos,
            direction: farPos.minus(nearPos).normalized()
        }
    }

    function intersectPlane(ray: var, planeNormal: vector3d, planePoint: vector3d) : var {
        const denom = ray.direction.dotProduct(planeNormal)
        if (Math.abs(denom) < 0.0001) return null

        const t = planePoint.minus(ray.origin).dotProduct(planeNormal) / denom
        return ray.origin.plus(ray.direction.times(t))
    }

    function getDirectionFromAngles(h: real, v: real) : vector3d {
        const rotVRad = v * Math.PI / 180
        const rotHRad = h * Math.PI / 180
        return Qt.vector3d(
            -Math.cos(rotVRad) * Math.sin(rotHRad),
            Math.sin(rotVRad),
            -Math.cos(rotVRad) * Math.cos(rotHRad)
        )
    }

    function updateRotationToTarget() : void {
        if (!hasTarget || updatingRotation || !ready) return

        const currentPos = Qt.vector3d(root.positionX, root.positionY, root.positionZ)
        const dir = targetPoint.minus(currentPos)

        // Calculate rotation to look at target
        // Horizontal (yaw): rotation around Y axis.
        // Use -dx because positive rotation (counter-clockwise) points to -X (Left)
        const hAngle = Math.atan2(-dir.x, -dir.z) * 180 / Math.PI

        // Vertical (pitch): rotation around X axis.
        const distXZ = Math.sqrt(dir.x * dir.x + dir.z * dir.z)
        const vAngle = Math.atan2(dir.y, distXZ) * 180 / Math.PI

        root.updatingRotation = true
        root.rotationHorizontal = clamp(hAngle, -root.maxRotationAngle, root.maxRotationAngle)
        root.rotationVertical = clamp(vAngle, -root.maxRotationAngle, root.maxRotationAngle)
        root.updatingRotation = false
    }

    function updateTargetFromRotation() : void {
        if (root.updatingRotation) return

        const dir = getDirectionFromAngles(root.rotationHorizontal, root.rotationVertical)
        const planeZ = -root.displayDistance

        // Check if ray points towards plane (dirZ should be negative)
        if (dir.z < -0.0001) {
            const t = (planeZ - root.positionZ) / dir.z
            if (t > 0) {
                // We update the target point regardless of whether it's inside the display bounds
                root.targetPoint = Qt.vector3d(
                    root.positionX + dir.x * t,
                    root.positionY + dir.y * t,
                    planeZ
                )
                root.hasTarget = true
            } else {
                root.hasTarget = false
            }
        } else {
            root.hasTarget = false
        }
    }

    function updateTargetFromMouse(mousePos: vector2d) : void {
        const ray = getRay(mousePos.x, mousePos.y)

        // Intersect with display plane (Z = -displayDistance)
        const hit = intersectPlane(ray, Qt.vector3d(0, 0, 1), Qt.vector3d(0, 0, -root.displayDistance))

        if (hit) {
            // Clamp to display bounds with margin
            const limitX = (root.displayWidth / 2.0) * 0.98
            const limitY = (root.displayHeight / 2.0) * 0.98

            const clampedX = clamp(hit.x, -limitX, limitX)
            const clampedY = clamp(hit.y, -limitY, limitY)

            root.targetPoint = Qt.vector3d(clampedX, clampedY, hit.z)
            root.hasTarget = true
            root.updateRotationToTarget()
        }
    }

    // --- 3D Scene ---

    View3D {
        id: view3d
        anchors.fill: parent
        camera: camera

        environment: SceneEnvironment {
            clearColor: "#2a2a2a"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        Node {
            id: cameraOrigin
            eulerRotation.x: 0

            PerspectiveCamera {
                id: camera
                z: 0
            }
        }

        DirectionalLight {
            eulerRotation.x: -30
            eulerRotation.y: -30
            ambientColor: "#404040"
        }

        DirectionalLight {
            eulerRotation.x: -30
            eulerRotation.y: 150
            brightness: 0.5
        }

        Node {
            id: sceneRoot

            // Grid floor for spatial reference
            Repeater3D {
                model: 21
                Node {
                    y: -160
                    Model {
                        x: (index - 10) * 40
                        scale: Qt.vector3d(0.005, 0.005, 8)
                        source: "#Cube"
                        materials: PrincipledMaterial {
                            baseColor: "#555555"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        z: (index - 10) * 40
                        scale: Qt.vector3d(8, 0.005, 0.005)
                        source: "#Cube"
                        materials: PrincipledMaterial {
                            baseColor: "#555555"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                }
            }

            // Head model
            Model {
                id: headModel
                objectName: "headModel"
                source: "#Sphere"
                scale: Qt.vector3d(0.12, 0.14, 0.12)
                visible: camera.scenePosition.length() > 17
                opacity: 0.4
                materials: PrincipledMaterial {
                    baseColor: "#8899aa"
                    roughness: 0.7
                }

                // Eyes
                Repeater3D {
                    model: 2
                    delegate: Model {
                        source: "#Cube"
                        visible: headModel.visible
                        position: Qt.vector3d(index ? -20 : 20, 12, -48)
                        scale: Qt.vector3d(0.13, 0.13, 0.13)
                        materials: PrincipledMaterial {
                            baseColorMap: Texture {
                                sourceItem: kdeWhite
                            }
                        }
                        SequentialAnimation on eulerRotation.z {
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: index ? 0 : 360
                                to: index ? 360 : 0
                                duration: 2000
                            }
                        }
                    }
                }
            }

            // Ray origin node
            Node {
                id: rayOrigin
                position: Qt.vector3d(root.positionX, root.positionY, root.positionZ).times(root.sceneScale)
                eulerRotation.x: root.rotationVertical
                eulerRotation.y: root.rotationHorizontal

                // Ray visualization
                Model {
                    id: rayModel
                    eulerRotation.x: -90
                    scale: Qt.vector3d(0.02, root.rayLength / 100, 0.02)
                    source: "#Cone"
                    opacity: 0.8
                    materials: PrincipledMaterial {
                        baseColor: root.rayColor
                        lighting: PrincipledMaterial.NoLighting
                    }
                }

                // Dotted ray for low visibility colors (alpha < 40%)
                Repeater3D {
                    model: Math.floor(root.rayLength / 10)
                    Model {
                        source: "#Sphere"
                        scale: Qt.vector3d(0.01 / 3, 0.01 / 3, 0.03)
                        z: -(index + 1) * 10
                        visible: root.rayColor.a < 0.4
                        opacity: 0.5
                        materials: PrincipledMaterial {
                            baseColor: "#808080"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                }
            }

            // Position handle
            Node {
                id: positionHandle
                position: Qt.vector3d(root.positionX, root.positionY, root.positionZ).times(root.sceneScale)

                Model {
                    id: positionHandleModel
                    objectName: "positionHandle"
                    pickable: true
                    source: "#Sphere"

                    readonly property real distanceToCamera: scenePosition.minus(camera.scenePosition).length()
                    readonly property real scaleFactor: Math.max(0.01, distanceToCamera / 80.0)

                    scale: Qt.vector3d(
                        root.positionHandleRadius / 50 * scaleFactor,
                        root.positionHandleRadius / 50 * scaleFactor,
                        root.positionHandleRadius / 50 * scaleFactor
                    )

                    materials: PrincipledMaterial {
                        baseColor: positionHandleModel.hovered ? "#ffff00" : "#ff8800"
                        lighting: PrincipledMaterial.NoLighting
                    }
                    property bool hovered: false
                }
            }

            // Connection line
            Node {
                id: connectionLine
                property vector3d start: Qt.vector3d(0, 0, 0)
                property vector3d end: Qt.vector3d(
                    root.positionX * root.sceneScale,
                    root.positionY * root.sceneScale,
                    root.positionZ * root.sceneScale
                )
                property vector3d midpoint: start.plus(end).times(0.5)
                property real length: start.minus(end).length()
                property vector3d direction: end.minus(start).normalized()

                Model {
                    position: connectionLine.midpoint
                    // Align cylinder (along Z after rotation)
                    scale: Qt.vector3d(0.01 / 3, 0.01 / 3, connectionLine.length / 100)
                    source: "#Cylinder"
                    visible: camera.scenePosition.length() > 5
                    eulerRotation: calculateRotation()
                    opacity: 0.5
                    materials: PrincipledMaterial {
                        baseColor: "#888888"
                        lighting: PrincipledMaterial.NoLighting
                    }

                    function calculateRotation() : vector3d {
                        const dir = connectionLine.direction
                        if (dir.length() < 0.001) return Qt.vector3d(0, 0, 0)
                        const pitch = -Math.asin(dir.y) * 180 / Math.PI
                        const yaw = Math.atan2(dir.x, dir.z) * 180 / Math.PI
                        return Qt.vector3d(pitch, yaw, 0)
                    }
                }
            }

            // Virtual display
            Model {
                id: displayModel
                objectName: "displayModel"
                pickable: true
                position: Qt.vector3d(0, 0, -root.displayDistance)
                scale: Qt.vector3d(root.displayWidth / 100.0, root.displayHeight / 100.0, 0.01)
                source: "#Cube"
                opacity: root.displayModelHovered ? 0.5 : 0.3
                materials: PrincipledMaterial {
                    baseColor: root.displayModelHovered ? "#6688aa" : "#446688"
                    lighting: PrincipledMaterial.NoLighting
                }
            }

            // Ray-display intersection point
            Model {
                id: intersectionPoint
                source: "#Sphere"
                scale: Qt.vector3d(0.03, 0.03, 0.03)
                materials: PrincipledMaterial {
                    baseColor: "#ff0000"
                    lighting: PrincipledMaterial.NoLighting
                }

                property vector3d hitPos: calculateHit()

                function calculateHit() : vector3d {
                    const ray = { origin: rayOrigin.scenePosition, direction: rayOrigin.forward }
                    // Intersect with plane Z = -root.displayDistance
                    const hit = intersectPlane(ray, Qt.vector3d(0, 0, 1), Qt.vector3d(0, 0, -root.displayDistance))
                    return hit ? hit : Qt.vector3d(0,0,0)
                }

                position: hitPos

                // Visibility check
                visible: {
                    // Ensure looking forward (-Z)
                    if (rayOrigin.forward.z >= -0.0001) return false

                    return Math.abs(hitPos.x) <= root.displayWidth / 2.0 &&
                           Math.abs(hitPos.y) <= root.displayHeight / 2.0
                }
            }
        }
    }

    // --- Input Handling ---

    property bool displayModelHovered: false

    // 1. Orbit Handler (LMB, threshold 0, active on empty space)
    DragHandler {
        id: orbitHandler
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: 0
        enabled: active || (!interactionHandler.active && !zDragHandler.active && !positionHandleModel.hovered && !root.displayModelHovered)

        property point lastPos
        onActiveChanged: {
            if (active) lastPos = centroid.position
        }
        onCentroidChanged: {
            if (active) {
                const deltaX = centroid.position.x - lastPos.x
                const deltaY = centroid.position.y - lastPos.y
                const sensitivity = 0.5

                cameraOrigin.eulerRotation.y -= deltaX * sensitivity
                cameraOrigin.eulerRotation.x -= deltaY * sensitivity
                cameraOrigin.eulerRotation.x = clamp(cameraOrigin.eulerRotation.x, -90, 90)

                lastPos = centroid.position
            }
        }
    }

    // 2. Interaction Handler (LMB, threshold 5, active on objects)
    DragHandler {
        id: interactionHandler
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: 5
        enabled: active || positionHandleModel.hovered || root.displayModelHovered

        property int mode: 0 // 1: XY Move, 2: Display Dragging
        property vector3d offset: Qt.vector3d(0,0,0)

        onActiveChanged: {
            if (active) {
                const pick = view3d.pick(centroid.position.x, centroid.position.y)
                const name = pick.objectHit ? pick.objectHit.objectName : ""
                if (name === "positionHandle") {
                    mode = 1
                    offset = pick.scenePosition.minus(Qt.vector3d(root.positionX, root.positionY, root.positionZ))
                } else if (name === "displayModel") {
                    mode = 2
                    root.updateTargetFromMouse(centroid.position)
                } else {
                    mode = 0
                }
            } else {
                mode = 0
            }
        }

        onCentroidChanged: {
            if (!active) return
            if (mode === 1) {
                const ray = getRay(centroid.position.x, centroid.position.y)
                const hit = intersectPlane(ray, Qt.vector3d(0, 0, 1), Qt.vector3d(0, 0, root.positionZ))
                if (hit) {
                    root.positionX = clamp(hit.x - offset.x, -50, 50)
                    root.positionY = clamp(hit.y - offset.y, -50, 50)
                }
            } else if (mode === 2) {
                root.updateTargetFromMouse(centroid.position)
            }
        }
    }

    // 3. Tap Handler (LMB, for clicks on display)
    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: root.displayModelHovered
        onTapped: root.updateTargetFromMouse(point.position)
    }

    // 4. Zoom Handler
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: (event)=> {
            const delta = event.angleDelta.y
            if (delta === 0) return

            const factor = Math.pow(1.1, delta / 120.0)
            let newZ = camera.z

            if (delta < 0) {
                if (newZ < 1.0) {
                    newZ += 2.0
                } else {
                    newZ /= 0.9
                }
            } else {
                newZ *= 0.9
                if (newZ < 0.1) newZ = 0
            }

            camera.z = clamp(newZ, 0, 250)
        }
    }

    // 5. Hover Feedback
    HoverHandler {
        id: hoverHandler
        onPointChanged: {
            const pick = view3d.pick(point.position.x, point.position.y)
            const name = pick.objectHit ? pick.objectHit.objectName : ""
            positionHandleModel.hovered = (name === "positionHandle")
            root.displayModelHovered = (name === "displayModel")
        }
    }

    // 6. Z-Move Handler (RMB)
    DragHandler {
        id: zDragHandler
        target: null
        acceptedButtons: Qt.RightButton
        enabled: active || positionHandleModel.hovered
        dragThreshold: 0

        property bool draggingZ: false
        property real offsetZ: 0

        onActiveChanged: {
            if (active) {
                const pick = view3d.pick(centroid.position.x, centroid.position.y)
                if (pick.objectHit && pick.objectHit.objectName === "positionHandle") {
                    draggingZ = true
                    offsetZ = pick.scenePosition.z - root.positionZ
                } else {
                    draggingZ = false
                }
            } else {
                draggingZ = false
            }
        }

        onCentroidChanged: {
            if (!active || !draggingZ) return

            const ray = getRay(centroid.position.x, centroid.position.y)
            // Intersect with plane Y = root.positionY (horizontal plane relative to camera)
            const hit = intersectPlane(ray, Qt.vector3d(0, 1, 0), Qt.vector3d(0, root.positionY, 0))

            if (hit) {
                root.positionZ = clamp(hit.z - offsetZ, -50, 50)
            }
        }
    }

    // --- UI Overlays ---

    Controls.Label {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 8
        text: i18nc("@info:tooltip", "Click/Drag on display: point ray\nLeft-drag orange sphere: move X/Y\nRight-drag orange sphere: move Z\nLeft-drag elsewhere: orbit camera | Scroll: zoom")
        color: "#aaaaaa"
        font.pointSize: 8
    }

    Controls.Label {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        text: i18nc("@label", "Cam Pos: %1, %2, %3\nCam Rot: %4, %5, %6",
            camera.scenePosition.x.toFixed(1),
            camera.scenePosition.y.toFixed(1),
            camera.scenePosition.z.toFixed(1),
            cameraOrigin.eulerRotation.x.toFixed(1),
            cameraOrigin.eulerRotation.y.toFixed(1),
            cameraOrigin.eulerRotation.z.toFixed(1))
        color: "#aaaaaa"
        font.pointSize: 8
    }

    Controls.Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        icon.name: "view-restore"
        text: ""
        padding: 4
        onClicked: {
            camera.z = 0
            cameraOrigin.eulerRotation = Qt.vector3d(0, 0, 0)
        }
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: i18nc("@action:button", "Reset Camera")
    }

    Controls.Label {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        text: i18nc("@label", "X: %1  Y: %2  Z: %3 cm\nH: %4  V: %5 deg",
            root.positionX.toFixed(1),
            root.positionY.toFixed(1),
            root.positionZ.toFixed(1),
            root.rotationHorizontal.toFixed(1),
            root.rotationVertical.toFixed(1))
        color: "#cccccc"
        font.pointSize: 9
        horizontalAlignment: Text.AlignRight
    }
}
