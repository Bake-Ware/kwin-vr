/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * PlaneControlTab — decoration overlay for a CurvedPlane.
 *
 * Renders a small Plasma-styled tab at the top edge of the plane's
 * bounding box. Two button rows: curvature ± and (containers only) dissolve.
 * Visibility tied to KWinVRConfig.hideControlTabsOnIdle (hover-only) and
 * the suppression flag (hosted-by-pseudomirror).
 *
 * Implementation: Item composed at 240×60 px, projected through a
 * Texture { sourceItem: Item } onto a flat Model — same pattern as
 * VrHudPlane's debug overlay.
 */

import QtQuick
import QtQuick.Controls
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    required property var plane
    property bool hovered: false

    signal dissolveRequested()
    signal curvatureNudge(real direction)

    readonly property bool isContainer: plane && plane.content === null

    // Tab dimensions in world units (cm at ppu 100).
    readonly property real tabW: 0.16
    readonly property real tabH: 0.04

    readonly property real planeH: plane ? plane.effectiveSize.height : 1

    position: Qt.vector3d(0, planeH / 2 + tabH / 2 + 0.005, 0)

    visible: !KWinVRConfig.hideControlTabsOnIdle || hovered

    Model {
        source: "#Rectangle"
        scale: Qt.vector3d(root.tabW / 100, root.tabH / 100, 1)
        depthBias: -150 * KWinVRConfig.depthBiasMultiplier

        materials: PrincipledMaterial {
            baseColorMap: Texture {
                sourceItem: Item {
                    id: tabContent
                    width: 320
                    height: 80

                    Rectangle {
                        anchors.fill: parent
                        color: "#202225"
                        radius: 12
                        border.color: "#444"
                        border.width: 1
                        opacity: 0.92
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Button {
                            text: "∿+"
                            font.pixelSize: 28
                            width: 70
                            height: 60
                            onClicked: root.curvatureNudge(1.0)
                        }
                        Button {
                            text: "∿−"
                            font.pixelSize: 28
                            width: 70
                            height: 60
                            onClicked: root.curvatureNudge(-1.0)
                        }
                        Button {
                            text: "✕"
                            font.pixelSize: 24
                            visible: root.isContainer
                            width: 70
                            height: 60
                            onClicked: root.dissolveRequested()
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
