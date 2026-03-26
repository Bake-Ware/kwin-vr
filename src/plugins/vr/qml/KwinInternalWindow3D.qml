/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick3D
import QtQuick3D.Helpers
import QtQuick3D.Xr

import org.kde.kwin.vr

/* KWin internal window as 3D rectangle model (without any decrotaions or shadows) */
Node {
    id: root
    property real ppu: 20
    property alias grabHandle: model.grabHandle
    property alias pickable: model.pickable
    readonly property Model windowModel: model

    property rect clientSize: this.client ? this.client.clientGeometry : Qt.rect(0,0,1,1)
    property size surfaceSize: this.surface ? this.surface.size : Qt.size(0,0)

    property zMargins itemDepth: ({
                                  top: root.visible ? KWinVRConfig.zWindowMarginTop : 0,
                                  bottom: root.visible ? KWinVRConfig.zWindowMarginBottom : 0
                              })
    property real zOffset: 0
    property real zOffsetGlobal: 0

    /* KWin::Window */
    property QtObject client
    visible: this.client && !this.client.minimized && this.client.opacity > 0 && (this.clientSize.width > 1 && this.clientSize.height > 1) && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    function uvToWindow2DCoordinates(coords: vector2d): point {
        return Qt.point(
                    (coords.x * root.clientSize.width),
                    (1 - coords.y) * root.clientSize.height)
    }

    Model {
        id: model
        property Node grabHandle: root
        pickable: root.visible
        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier

        source: "#Rectangle"
        materials: WindowTextureMaterial {
            id: material
            texture: Texture {
                sourceItem: KwinInternalWindow {
                    id: kwinInternalWin
                    client: root.client
                }
                flipU: kwinInternalWin.flipU
                flipV: kwinInternalWin.flipV
            }
        }

        scale: Qt.vector3d(root.clientSize.width/100/root.ppu,
                           root.clientSize.height/100/root.ppu,
                           0.01)

        // position: Qt.vector3d(this.surfaceSize.width/2/root.ppu, -this.surfaceSize.height/2/root.ppu, 0)
    }
}
