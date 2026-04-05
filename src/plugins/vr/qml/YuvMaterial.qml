/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/**
 * Custom material for rendering YUV (NV12/P010) surfaces.
 * Performs YUV to RGB color space conversion in the fragment shader.
 */
CustomMaterial {
    id: root

    property TextureInput yTexture: TextureInput {
        enabled: true
    }

    property TextureInput uvTexture: TextureInput {
        enabled: true
    }

    property vector4d uvTransform: Qt.vector4d(0.0, 1.0, 1.0, -1.0)
    property matrix4x4 yuvToRgb

    states: State {
        name: "hasTexture"
        when: yTexture.texture

        PropertyChanges {
            target: root
            uvTransform: {
                let tex = yTexture.texture
                let posU = tex.positionU
                let sclU = tex.scaleU
                let posV = tex.positionV
                let sclV = tex.scaleV
                let flipU = tex.flipU
                // autoOrientation flips V, flipV is additional flip (XOR)
                let flipV = tex.autoOrientation !== tex.flipV

                return Qt.vector4d(
                    flipU ? 1.0 - posU : posU,
                    flipU ? -sclU : sclU,
                    flipV ? 1.0 - posV : posV,
                    flipV ? -sclV : sclV
                )
            }
        }
    }

    shadingMode: CustomMaterial.Unshaded
    cullMode: Material.BackFaceCulling
    depthDrawMode: Material.AlwaysDepthDraw

    vertexShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/yuv.vert"
    fragmentShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/yuv.frag"
}
