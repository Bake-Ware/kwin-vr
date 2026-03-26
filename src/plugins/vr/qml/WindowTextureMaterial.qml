/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/**
 * This material is needed only becacause it can handle premultiplied alpha :(
 */
CustomMaterial {
    id: root

    property alias texture: texInput.texture
    property TextureInput baseColorMap: texInput
    TextureInput {
        id: texInput
        enabled: true
    }

    property vector4d uvTransform: {
        const tex = texInput.texture
        if (!tex) {
            return Qt.vector4d(0.0, 1.0, 0.0, 1.0)
        }

        const posU = tex.positionU
        const sclU = tex.scaleU
        const posV = tex.positionV
        const sclV = tex.scaleV
        const flipU = tex.flipU
        const flipV = tex.autoOrientation !== tex.flipV

        return Qt.vector4d(
            flipU ? 1.0 - posU : posU,
            flipU ? -sclU : sclU,
            flipV ? 1.0 - posV : posV,
            flipV ? -sclV : sclV
        )
    }

    property bool isOpaque: false

    shadingMode: CustomMaterial.Unshaded
    sourceBlend: root.isOpaque ? CustomMaterial.NoBlend : CustomMaterial.One
    destinationBlend: root.isOpaque ? CustomMaterial.NoBlend : CustomMaterial.OneMinusSrcAlpha
    depthDrawMode: root.isOpaque ? Material.AlwaysDepthDraw : Material.OpaqueOnlyDepthDraw

    vertexShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/window_texture.vert"
    fragmentShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/window_texture.frag"
}
