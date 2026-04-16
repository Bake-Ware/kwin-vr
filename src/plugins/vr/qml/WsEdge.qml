/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

// Thin cylinder drawn between two endpoints. Used to render primitive wireframes.
// Qt Quick 3D #Cylinder is 100 units tall along Y and 50 unit radius. We scale
// radius to (thickness/100)*50 and height to length/100.
Model {
    id: root
    required property vector3d edgeFrom
    required property vector3d edgeTo
    property real thickness: 0.3
    property color edgeColor: "#e0ffffff"

    source: "#Cylinder"
    castsShadows: false
    receivesShadows: false
    depthBias: 20

    readonly property vector3d _delta: Qt.vector3d(edgeTo.x - edgeFrom.x,
                                                   edgeTo.y - edgeFrom.y,
                                                   edgeTo.z - edgeFrom.z)
    readonly property real _len: Math.sqrt(_delta.x*_delta.x + _delta.y*_delta.y + _delta.z*_delta.z)

    position: Qt.vector3d((edgeFrom.x + edgeTo.x) * 0.5,
                          (edgeFrom.y + edgeTo.y) * 0.5,
                          (edgeFrom.z + edgeTo.z) * 0.5)

    scale: Qt.vector3d(thickness / 100, Math.max(_len, 0.0001) / 100, thickness / 100)

    rotation: _len > 0.0001
              ? KwinVrHelpers.rotationBetweenVectors(Qt.vector3d(0, 1, 0), _delta)
              : Qt.quaternion(1, 0, 0, 0)

    materials: PrincipledMaterial {
        baseColor: root.edgeColor
        alphaMode: PrincipledMaterial.Blend
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.NoCulling
    }
}
