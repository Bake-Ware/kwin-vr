/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

Node {
    id: root

    property real ppu: 20
    position: Qt.vector3d(-10, 5, -60)
    required property Xray ray
    required property pickResult lastPick

    Model {
        id: model

        // Offset so the Node's origin is at the top-left of the HUD
        x: hudItem.width / 2 / root.ppu / hudItem.contentScale
        y: -hudItem.height / 2 / root.ppu / hudItem.contentScale

        source: "#Rectangle"

        /* Make the HUD visible */
        depthBias: -10000
        materials: PrincipledMaterial {
            baseColorMap: Texture {
                sourceItem: XrayHudItem {
                    id: hudItem
                    pickResult: root.lastPick
                }
            }

            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            depthDrawMode: Material.OpaqueOnlyDepthDraw
        }
        scale: Qt.vector3d(hudItem.width / 100 / root.ppu / hudItem.contentScale,
                           hudItem.height / 100 / root.ppu / hudItem.contentScale,
                           0.001)
    }
}
