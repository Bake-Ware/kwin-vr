/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * PlaneControlTab — decoration overlay for a CurvedPlane.
 *
 * Renders a small Plasma-styled tab at the top edge of the plane's
 * bounding box. Two buttons:
 *   - curvature toggle (stub for phase 1, no slider yet)
 *   - dissolve (containers only)
 *
 * Visibility:
 *   - never on hosted-by-pseudomirror children
 *   - controlled by `enabled` property otherwise
 *   - global hide-on-idle setting collapses to hover-only
 */

import QtQuick
import QtQuick.Controls
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    required property CurvedPlane plane
    property bool enabledTab: true
    property bool isContainer: false
    property bool hovered: false

    signal dissolveRequested()
    signal curvatureNudge(real direction)

    // Tab dimensions in world units
    readonly property real tabW: 0.12
    readonly property real tabH: 0.03

    // Anchor at top edge of plane content. plane.effectiveSize is the
    // content world size.
    readonly property real planeW: plane ? plane.effectiveSize.width : 1
    readonly property real planeH: plane ? plane.effectiveSize.height : 1

    position: Qt.vector3d(0, planeH / 2 + tabH / 2 + 0.005, 0)

    visible: enabledTab
             && (!KWinVRConfig.hideControlTabsOnIdle || hovered)

    Item {
        id: tabContent
        width: 240
        height: 60
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            color: "#202225"
            radius: 8
            border.color: "#444"
            border.width: 1
            opacity: 0.9
        }

        Row {
            anchors.centerIn: parent
            spacing: 8
            Button {
                text: "∿"
                font.pixelSize: 24
                width: 50
                height: 44
                onClicked: root.curvatureNudge(1.0)
            }
            Button {
                text: "↺"
                font.pixelSize: 22
                width: 50
                height: 44
                onClicked: root.curvatureNudge(-1.0)
            }
            Button {
                text: "✕"
                font.pixelSize: 22
                visible: root.isContainer
                width: 50
                height: 44
                onClicked: root.dissolveRequested()
            }
        }
    }

    Model {
        source: "#Rectangle"
        scale: Qt.vector3d(tabW / 100, tabH / 100, 1)
        depthBias: -150 * KWinVRConfig.depthBiasMultiplier
        materials: DefaultMaterial {
            diffuseMap: Texture {
                sourceItem: tabContent
            }
            lighting: DefaultMaterial.NoLighting
        }
    }
}
