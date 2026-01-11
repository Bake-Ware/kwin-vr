/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

Node {
    id: root
    // TODO: ppu should be taken from hovered object
    property real ppu: 20
    property real hoverDistance: -0.015
    function calcHoveredPosition(scenePos: vector3d, sceneNormal: vector3d): vector3d {
        return scenePos.minus(sceneNormal.normalized().times(root.hoverDistance))
    }

    Model {
        source: "#Rectangle"

        /* Make the cursor visible */
        depthBias: -10000
        materials: WindowTextureMaterial {
            texture: Texture {
                sourceItem: KwinCurrentCursor {
                    id: cur
                }
            }
        }
        property real sc: 1/root.ppu/cur.pixelRatio
        position: Qt.vector3d(
                      (0.5 - (cur.hotspot.x / cur.width)) * sc * cur.psize.width,
                      (-0.5 + (cur.hotspot.y / cur.height)) * sc * cur.psize.height,
                      0)
        scale: Qt.vector3d(cur.psize.width/100 * sc, cur.psize.height/100 * sc, 0.001)

        visible: cur.psize.width > 0
    }
}
