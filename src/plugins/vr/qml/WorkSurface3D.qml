/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    property string surfaceId: ""
    property int shapeType: 0
    property real ppu: 20
    property bool selected: false
    property real baseFaceWidth: 60
    property real baseFaceHeight: 40
    property size itemSize: Qt.size(baseFaceWidth, baseFaceHeight)
    property Node grabHandle: root
    property var faces: []
    property var surfaceModel: null
    property bool _initialized: false

    onPositionChanged: persistTransform()
    onRotationChanged: persistTransform()
    onScaleChanged: persistTransform()

    function persistTransform() {
        if (!_initialized || !root.surfaceModel) return
        root.surfaceModel.updateTransform(root.surfaceId, root.position, root.rotation, root.scale)
    }

    // Shape loader
    Loader3D {
        id: shapeLoader
        sourceComponent: {
            switch (root.shapeType) {
            case 0: return planeComponent
            case 1: return cubeComponent
            case 2: return cylinderComponent
            case 3: return pyramidComponent
            case 4: return sphereComponent
            default: return planeComponent
            }
        }
    }

    // ---- Shared face helper ----
    function makeFace(faceWidth, faceHeight) {
        return {
            faceWidth: faceWidth,
            faceHeight: faceHeight
        }
    }

    // ---- Wireframe face component used by all shapes ----
    Component {
        id: wireframeFace
        Model {
            property real faceWidth: 60
            property real faceHeight: 40
            property Node grabHandle: root
            property int stackingOrder: 0
            source: "#Rectangle"
            pickable: true
            scale: Qt.vector3d(faceWidth / 100, faceHeight / 100, 0.001)
            materials: PrincipledMaterial {
                baseColorMap: Texture {
                    sourceItem: Rectangle {
                        width: 400; height: 400
                        color: "#1800ccff"
                        border.color: "#aa00ccff"
                        border.width: 8; radius: 12
                        Rectangle { width: 30; height: 30; color: parent.border.color; radius: 4 }
                        Rectangle { x: parent.width - 30; width: 30; height: 30; color: parent.border.color; radius: 4 }
                        Rectangle { y: parent.height - 30; width: 30; height: 30; color: parent.border.color; radius: 4 }
                        Rectangle { x: parent.width - 30; y: parent.height - 30; width: 30; height: 30; color: parent.border.color; radius: 4 }
                        Rectangle { anchors.centerIn: parent; width: 40; height: 2; color: parent.border.color; opacity: 0.6 }
                        Rectangle { anchors.centerIn: parent; width: 2; height: 40; color: parent.border.color; opacity: 0.6 }
                    }
                }
                alphaMode: PrincipledMaterial.Blend
                lighting: PrincipledMaterial.NoLighting
                depthDrawMode: Material.OpaqueOnlyDepthDraw
            }
            depthBias: 50
        }
    }

    // ========================================================================
    // PLANE — single forward-facing face
    // ========================================================================
    Component {
        id: planeComponent
        Node {
            Loader3D {
                sourceComponent: wireframeFace
                onLoaded: item.faceWidth = root.baseFaceWidth
                Component.onCompleted: if(item) item.faceHeight = root.baseFaceHeight
            }
        }
    }

    // ========================================================================
    // CUBE — 6 faces
    // ========================================================================
    Component {
        id: cubeComponent
        Node {
            property real s: root.baseFaceWidth
            property real h: root.baseFaceHeight

            // Front
            Node {
                position: Qt.vector3d(0, 0, s / 2)
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = h }
                }
            }
            // Back
            Node {
                position: Qt.vector3d(0, 0, -s / 2)
                eulerRotation.y: 180
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = h }
                }
            }
            // Left
            Node {
                position: Qt.vector3d(-s / 2, 0, 0)
                eulerRotation.y: -90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = h }
                }
            }
            // Right
            Node {
                position: Qt.vector3d(s / 2, 0, 0)
                eulerRotation.y: 90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = h }
                }
            }
            // Top
            Node {
                position: Qt.vector3d(0, h / 2, 0)
                eulerRotation.x: 90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = s }
                }
            }
            // Bottom
            Node {
                position: Qt.vector3d(0, -h / 2, 0)
                eulerRotation.x: -90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = s; item.faceHeight = s }
                }
            }
        }
    }

    // ========================================================================
    // CYLINDER — body + 2 caps, with visual cylinder mesh
    // ========================================================================
    Component {
        id: cylinderComponent
        Node {
            property real r: root.baseFaceWidth
            property real h: root.baseFaceHeight

            // Visual cylinder
            Model {
                source: "#Cylinder"
                scale: Qt.vector3d(r / 100, h / 100, r / 100)
                materials: PrincipledMaterial {
                    baseColor: "#18ffffff"
                    alphaMode: PrincipledMaterial.Blend
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            // Body face (front)
            Loader3D {
                sourceComponent: wireframeFace
                onLoaded: { item.faceWidth = r * Math.PI; item.faceHeight = h }
            }
            // Top cap
            Node {
                position: Qt.vector3d(0, h / 2, 0)
                eulerRotation.x: 90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = r; item.faceHeight = r }
                }
            }
            // Bottom cap
            Node {
                position: Qt.vector3d(0, -h / 2, 0)
                eulerRotation.x: -90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = r; item.faceHeight = r }
                }
            }
        }
    }

    // ========================================================================
    // PYRAMID — 4 slanted faces + base
    // ========================================================================
    Component {
        id: pyramidComponent
        Node {
            property real b: root.baseFaceWidth
            property real h: root.baseFaceHeight
            property real ang: Math.atan2(h, b / 2) * 180 / Math.PI
            property real fw: b * 0.7
            property real fh: h * 0.6

            // Front
            Node {
                position: Qt.vector3d(0, h * 0.25, b / 4)
                eulerRotation.x: -(90 - parent.ang)
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = parent.parent.fw; item.faceHeight = parent.parent.fh }
                }
            }
            // Back
            Node {
                position: Qt.vector3d(0, h * 0.25, -b / 4)
                eulerRotation.x: (90 - parent.ang)
                eulerRotation.y: 180
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = parent.parent.fw; item.faceHeight = parent.parent.fh }
                }
            }
            // Left
            Node {
                position: Qt.vector3d(-b / 4, h * 0.25, 0)
                eulerRotation.y: -90
                eulerRotation.x: -(90 - parent.ang)
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = parent.parent.fw; item.faceHeight = parent.parent.fh }
                }
            }
            // Right
            Node {
                position: Qt.vector3d(b / 4, h * 0.25, 0)
                eulerRotation.y: 90
                eulerRotation.x: -(90 - parent.ang)
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = parent.parent.fw; item.faceHeight = parent.parent.fh }
                }
            }
            // Base
            Node {
                eulerRotation.x: -90
                Loader3D {
                    sourceComponent: wireframeFace
                    onLoaded: { item.faceWidth = b; item.faceHeight = b }
                }
            }
        }
    }

    // ========================================================================
    // SPHERE — 6 patches + visual sphere mesh
    // ========================================================================
    Component {
        id: sphereComponent
        Node {
            property real r: root.baseFaceWidth / 2
            property real fs: r * 1.2

            // Visual sphere
            Model {
                source: "#Sphere"
                scale: Qt.vector3d(r / 50, r / 50, r / 50)
                materials: PrincipledMaterial {
                    baseColor: "#18ffffff"
                    alphaMode: PrincipledMaterial.Blend
                    lighting: PrincipledMaterial.NoLighting
                }
            }
            // Front
            Node {
                position: Qt.vector3d(0, 0, parent.r)
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
            // Back
            Node {
                position: Qt.vector3d(0, 0, -parent.r)
                eulerRotation.y: 180
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
            // Left
            Node {
                position: Qt.vector3d(-parent.r, 0, 0)
                eulerRotation.y: -90
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
            // Right
            Node {
                position: Qt.vector3d(parent.r, 0, 0)
                eulerRotation.y: 90
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
            // Top
            Node {
                position: Qt.vector3d(0, parent.r, 0)
                eulerRotation.x: 90
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
            // Bottom
            Node {
                position: Qt.vector3d(0, -parent.r, 0)
                eulerRotation.x: -90
                Loader3D { sourceComponent: wireframeFace; onLoaded: { item.faceWidth = parent.parent.fs; item.faceHeight = parent.parent.fs } }
            }
        }
    }
}
