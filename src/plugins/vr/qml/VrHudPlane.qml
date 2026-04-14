/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D
import org.kde.kwin.vr

/*
 * HUD surface: a camera-pinned container analogous to KwinPseudoOutputMirror.
 *
 * Everything is rendered as part of the surface texture so it conforms
 * to curvature. The grid pattern and debug overlay are composited in
 * the 2D sourceItem, then mapped onto CurvedPlaneGeometry.
 *
 * Loaded when either hudEnabled or debugDisplayEnabled is active.
 */
Node {
    id: root

    required property real ppu
    required property int displayWidth
    required property int displayHeight
    property var lastPick: null

    // Surface dimensions in world cm
    readonly property real surfaceW: displayWidth / ppu * KWinVRConfig.hudScaleH
    readonly property real surfaceH: displayHeight / ppu * KWinVRConfig.hudScaleV

    // Derived from config
    readonly property real hudDistance: KWinVRConfig.distance * KWinVRConfig.hudDistanceFraction / 100.0
    readonly property real hudY: -(hudDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))

    position: Qt.vector3d(0, hudY, -hudDistance)

    Model {
        geometry: CurvedPlaneGeometry {
            width: root.surfaceW
            height: root.surfaceH
            curvature: KWinVRConfig.hudCurvature
        }

        depthBias: -10000

        materials: PrincipledMaterial {
            baseColorMap: Texture {
                // All HUD content composited as a single 2D layer
                sourceItem: Item {
                    id: hudContent
                    width: root.displayWidth
                    height: root.displayHeight

                    // Grid pattern (only when calibration enabled)
                    Canvas {
                        id: gridCanvas
                        anchors.fill: parent
                        visible: KWinVRConfig.hudEnabled

                        onPaint: {
                            const ctx = getContext("2d")
                            const w = width
                            const h = height
                            const step = Math.max(w, h) / 20

                            ctx.clearRect(0, 0, w, h)

                            ctx.fillStyle = Qt.rgba(0.05, 0.05, 0.15, 0.6)
                            ctx.fillRect(0, 0, w, h)

                            ctx.strokeStyle = Qt.rgba(0.3, 0.6, 1.0, 0.5)
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            for (let x = 0; x <= w; x += step) {
                                ctx.moveTo(x, 0)
                                ctx.lineTo(x, h)
                            }
                            for (let y = 0; y <= h; y += step) {
                                ctx.moveTo(0, y)
                                ctx.lineTo(w, y)
                            }
                            ctx.stroke()

                            ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, 0.8)
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.moveTo(w / 2, 0)
                            ctx.lineTo(w / 2, h)
                            ctx.moveTo(0, h / 2)
                            ctx.lineTo(w, h / 2)
                            ctx.stroke()

                            ctx.strokeStyle = Qt.rgba(0.3, 0.6, 1.0, 0.8)
                            ctx.lineWidth = 3
                            ctx.strokeRect(1, 1, w - 2, h - 2)

                            ctx.fillStyle = Qt.rgba(1.0, 1.0, 1.0, 0.9)
                            ctx.font = Math.round(h / 15) + "px sans-serif"
                            ctx.textAlign = "center"
                            ctx.fillText("HUD PLANE", w / 2, h / 2 - h / 8)
                            ctx.font = Math.round(h / 25) + "px sans-serif"
                            ctx.fillText(w + " x " + h, w / 2, h / 2 + h / 8)
                        }

                        Component.onCompleted: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }

                    // Debug pick overlay — positioned in chosen corner
                    Rectangle {
                        id: debugPanel
                        visible: KWinVRConfig.debugDisplayEnabled
                        width: debugLayout.implicitWidth + 50
                        height: debugLayout.implicitHeight + 40
                        color: Qt.rgba(0, 0, 0, 0.75)
                        radius: 10
                        border.color: "#66ffffff"
                        border.width: 1

                        readonly property int corner: KWinVRConfig.debugDisplayCorner
                        readonly property real margin: 20
                        x: (corner % 2 === 0) ? margin : parent.width - width - margin
                        y: (corner < 2) ? margin : parent.height - height - margin

                        GridLayout {
                            id: debugLayout
                            anchors.centerIn: parent
                            columns: 2
                            columnSpacing: 18
                            rowSpacing: 5

                            Label {
                                color: "#88ccff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: "Hit:"
                            }
                            Label {
                                color: "#ffffff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: {
                                    if (!root.lastPick) return "N/A"
                                    const obj = root.lastPick.itemHit || root.lastPick.objectHit
                                    if (!obj) return "N/A"
                                    if (obj.objectName) return obj.objectName
                                    const str = obj.toString()
                                    const m = str.match(/^(\w+)/)
                                    return m ? m[1] : str
                                }
                            }

                            Label {
                                color: "#88ccff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: "UV:"
                            }
                            Label {
                                color: "#ffffff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: root.lastPick
                                      ? "(" + root.lastPick.uvPosition.x.toFixed(2)
                                        + ", " + root.lastPick.uvPosition.y.toFixed(2) + ")"
                                      : "N/A"
                            }

                            Label {
                                color: "#88ccff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: "Scene:"
                            }
                            Label {
                                color: "#ffffff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: {
                                    if (!root.lastPick) return "N/A"
                                    const v = root.lastPick.scenePosition
                                    return "(" + v.x.toFixed(1) + ", " + v.y.toFixed(1) + ", " + v.z.toFixed(1) + ")"
                                }
                            }

                            Label {
                                color: "#88ccff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: "Dist:"
                            }
                            Label {
                                color: "#ffffff"
                                font.family: "monospace"
                                font.pixelSize: 20
                                text: root.lastPick ? root.lastPick.distance.toFixed(2) : "N/A"
                            }
                        }
                    }
                }
            }
            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            depthDrawMode: Material.OpaqueOnlyDepthDraw
        }
    }
}
