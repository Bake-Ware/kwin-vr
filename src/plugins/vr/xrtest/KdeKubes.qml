/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

Repeater3D {
    model: [
        "red",
        "green"
    ]
    delegate: Model {
        required property int index
        required property string modelData

        source: "#Cube"
        position: Qt.vector3d((-20 + (index * 40)), 0, 0)
        scale: Qt.vector3d(0.2, 0.2, 0.2)

        materials: PrincipledMaterial {
            baseColor: modelData
            alphaMode: PrincipledMaterial.Blend
            depthDrawMode: PrincipledMaterial.AlwaysDepthDraw
        }

        NumberAnimation on eulerRotation.y {
            duration: 10000
            easing.type: Easing.InOutQuad
            from: !!index * 360
            to: !index * 360
            running: true
            loops: Animation.Infinite
        }
    }
}
