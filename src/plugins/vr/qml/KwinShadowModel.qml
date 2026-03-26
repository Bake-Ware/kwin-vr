/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

Model {
    id: root
    property alias shadow: geom.shadow
    property alias width: geom.width
    property alias height: geom.height
    property real ppu: 20

    visible: root.shadow && root.width >= 5 && root.height >= 5

    geometry: ShadowGeometry {
        id: geom
    }

    scale: Qt.vector3d(1.0 / root.ppu, 1.0 / root.ppu, 1.0)

    materials: WindowTextureMaterial {
        texture: Texture {
            id: shadowTexture
            sourceItem: KwinShadowItem {
                shadow: root.shadow
            }
        }

        cullMode: Material.NoCulling
    }
}
