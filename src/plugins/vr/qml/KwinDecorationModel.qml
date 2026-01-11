/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/* This small model wrapper is needded for VrFocusControl
 * to properly deliver pointer motion to the decoration */
Model {
    id: root

    readonly property alias shadow: kwinDeco.shadow
    readonly property alias width: kwinDeco.width
    readonly property alias height: kwinDeco.height

    property alias kDecoration: kwinDeco.decoration
    property real ppu: 20

    geometry: DecorationGeometry {
        decoration: root.kDecoration
    }

    materials: WindowTextureMaterial {
        texture: Texture {
            sourceItem: KwinWindowDecoration {
                id: kwinDeco
            }
        }
        isOpaque: root.kDecoration ? root.kDecoration.opaque : true
    }

    scale: Qt.vector3d(1/root.ppu, 1/root.ppu, 0.01)

    function uvToWindow2DCoordinates(coords: vector2d): point {
        return Qt.point(coords.x * kwinDeco.width, (1 - coords.y) * kwinDeco.height)
    }
}
