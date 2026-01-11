/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick3D

/* Just a simple blue rectangle with slightly rounded corners */
Model {
    id: root
    source: "#Rectangle"

    property real ppu: 20
    property real frameWidth: 200
    property real frameHeight: 150
    property real thickness: 10
    property color frameColor: "#0816d0"

    depthBias: 100
    scale: Qt.vector3d(root.frameWidth / 100 / root.ppu, root.frameHeight / 100 / root.ppu, 0.001)
    materials: PrincipledMaterial {
        baseColorMap: Texture {
            sourceItem: Rectangle {
                width: root.frameWidth
                height: root.frameHeight
                color: "transparent"
                border.color: root.frameColor
                border.width: root.thickness
                radius: 10
            }
        }
        alphaMode: PrincipledMaterial.Blend
        lighting: PrincipledMaterial.NoLighting
        depthDrawMode: Material.OpaqueOnlyDepthDraw
    }
}
