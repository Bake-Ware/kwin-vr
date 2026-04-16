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
 * Standalone debug pick-info overlay pinned to camera.
 * Lives independently of the HUD calibration plane.
 * Corner placement controlled by KWinVRConfig.debugDisplayCorner.
 */
Node {
    id: root

    required property real ppu
    required property int displayWidth
    required property int displayHeight
    property var lastPick: null

    // HUD reference frame
    readonly property real hudDistance: KWinVRConfig.distance * KWinVRConfig.hudDistanceFraction / 100.0
    readonly property real hudY: -(hudDistance * Math.tan(KWinVRConfig.hudVerticalAngle * Math.PI / 180.0))

    // Half-extents of the HUD area in world cm
    readonly property real halfW: (root.displayWidth / root.ppu * KWinVRConfig.hudScaleH) / 2
    readonly property real halfH: (root.displayHeight / root.ppu * KWinVRConfig.hudScaleV) / 2

    // Corner: 0=TL, 1=TR, 2=BL, 3=BR
    readonly property int corner: KWinVRConfig.debugDisplayCorner
    readonly property real cornerX: (corner % 2 === 0) ? -halfW : halfW
    readonly property real cornerY: (corner < 2) ? halfH : -halfH

    // Nudge inward from corner so the panel doesn't hang off the edge
    readonly property real insetX: (corner % 2 === 0) ? 5 : -5
    readonly property real insetY: (corner < 2) ? -3 : 3

    position: Qt.vector3d(cornerX + insetX, hudY + cornerY + insetY, -hudDistance)

    Model {
        source: "#Rectangle"
        // Always render on top — never occluded by scene geometry
        depthBias: -10000

        scale: Qt.vector3d(
            panelItem.width / 100 / root.ppu,
            panelItem.height / 100 / root.ppu,
            0.001
        )

        materials: PrincipledMaterial {
            baseColorMap: Texture {
                sourceItem: Rectangle {
                    id: panelItem
                    width: debugLayout.implicitWidth + 50
                    height: debugLayout.implicitHeight + 40
                    color: Qt.rgba(0, 0, 0, 0.75)
                    radius: 10
                    border.color: "#66ffffff"
                    border.width: 1

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
            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            depthDrawMode: Material.OpaqueOnlyDepthDraw
        }
    }
}
