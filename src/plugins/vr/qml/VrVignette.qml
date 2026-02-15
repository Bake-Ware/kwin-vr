/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick3D

Model {
    id: root

    property real fadeWidth: 0.15

    visible: fadeWidth > 0
    source: "#Rectangle"
    // Keep large bounding box near camera to prevent frustum culling.
    // The vertex shader overrides position to a full-screen clip-space quad.
    z: -10
    scale: Qt.vector3d(100, 100, 1)

    materials: CustomMaterial {
        property real fadeWidth: root.fadeWidth

        shadingMode: CustomMaterial.Unshaded
        sourceBlend: CustomMaterial.SrcAlpha
        destinationBlend: CustomMaterial.OneMinusSrcAlpha
        depthDrawMode: Material.NeverDepthDraw
        cullMode: Material.NoCulling

        vertexShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/vignette.vert"
        fragmentShader: "qrc:/qt/qml/org/kde/kwin/vr/shaders/vignette.frag"
    }
}
