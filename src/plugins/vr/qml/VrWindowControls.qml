/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/*
 * A horizontal toolbar rendered below the center of a VR window.
 * Uses VRWindow so the KWinToQQuick3DInputBridge routes ray clicks to the 2D buttons.
 */
Node {
    id: root
    required property real ppu
    required property QtObject client
    required property Node windowNode
    property real curvature: 0

    signal grabRequested()
    signal curveChanged(real delta)
    signal pipRequested()

    // Position at bottom center of window, shifted down by half toolbar height
    readonly property real windowHalfHeight: (client?.frameGeometry.height ?? 0) / (2 * ppu)
    readonly property real toolbarHalfHeight: toolbar.height / (2 * ppu)
    y: -(windowHalfHeight + 1.5 + toolbarHalfHeight)

    // Match titlebar z: push forward past curved surface edges
    readonly property real curveProtrusion: {
        if (root.curvature < 0.001) return 0
        const w = root.client?.bufferGeometry.width ?? 0
        return w * Math.tan(root.curvature / 4) / (2 * root.ppu)
    }
    z: curveProtrusion + 0.1

    VRWindow {
        id: controlPanel
        property Node grabHandle: root.windowNode

        scale: Qt.vector3d(1/root.ppu, 1/root.ppu, 1)
        position: Qt.vector3d(-toolbar.width / (2 * root.ppu), toolbar.height / (root.ppu), 0)

        Row {
            id: toolbar
            property Node parent3d: controlPanel
            height: 50
            spacing: 6

            Rectangle {
                width: 70; height: toolbar.height; radius: 8
                color: grabMA.containsMouse ? "#5599ccff" : "#3366aadd"
                border.color: "#88bbddff"; border.width: 2
                Text {
                    anchors.centerIn: parent
                    text: "Grab"
                    font.family: "sans-serif"
                    font.pixelSize: 18; font.bold: true
                    color: "white"
                }
                MouseArea {
                    id: grabMA; anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.grabRequested()
                }
            }

            Rectangle {
                width: 55; height: toolbar.height; radius: 8
                color: curvUpMA.containsMouse ? "#5599ccff" : "#3366aadd"
                border.color: "#88bbddff"; border.width: 2
                Text {
                    anchors.centerIn: parent
                    text: "C +"
                    font.family: "sans-serif"
                    font.pixelSize: 18; font.bold: true
                    color: "white"
                }
                MouseArea {
                    id: curvUpMA; anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.curveChanged(0.5)
                }
            }

            Rectangle {
                width: 55; height: toolbar.height; radius: 8
                color: curvDnMA.containsMouse ? "#5599ccff" : "#3366aadd"
                border.color: "#88bbddff"; border.width: 2
                Text {
                    anchors.centerIn: parent
                    text: "C -"
                    font.family: "sans-serif"
                    font.pixelSize: 18; font.bold: true
                    color: "white"
                }
                MouseArea {
                    id: curvDnMA; anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.curveChanged(-0.5)
                }
            }

            Rectangle {
                width: 55; height: toolbar.height; radius: 8
                color: pipMA.containsMouse ? "#5599ccff" : "#3366aadd"
                border.color: "#88bbddff"; border.width: 2
                Text {
                    anchors.centerIn: parent
                    text: "PiP"
                    font.family: "sans-serif"
                    font.pixelSize: 18; font.bold: true
                    color: "white"
                }
                MouseArea {
                    id: pipMA; anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.pipRequested()
                }
            }
        }
    }
}
