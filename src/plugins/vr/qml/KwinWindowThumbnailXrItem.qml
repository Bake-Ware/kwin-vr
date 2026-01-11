/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import QtQuick3D
import QtQuick3D.Helpers
import QtQuick3D.Xr

import org.kde.kwin as KWinC
import org.kde.kwin.vr

/* This is a single and full KWin window packed in XrItem
 * It is rendered by KWin's WindowThumbnail, so it contains
 * all surfaces, shadows and decotations. Effects are also applied.
 *
 * WindowThumbnail uses KWin's native renderer to draw a window to the texture first (offscreen rendering),
 * So it is bad for performance, but the result is the same as ordinary 2D windows.
 *
 * it is similar to KwinWindowThumbnail3D, but the window is being drawn into 2D scene inside XrItem
 */

Node {
    id: root
    property QtObject client
    property alias grabHandle: xritem.grabHandle
    property alias ppu: xritem.pixelsPerUnit
    property alias eff: thumbWindow.layer.enabled

    visible: !this.client.minimized && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    property zMargins itemDepth: ({
                                      top: root.visible ? KWinVRConfig.zWindowMarginTop : 0,
                                      bottom: root.visible ? KWinVRConfig.zWindowMarginBottom : 0
                                  })
    property real zOffsetGlobal: 0

    // Identity converter for compatibility with rayInputHandlers table
    // XrItem picking already returns pixel coordinates
    function uvToWindow2DCoordinates(uv: vector2d): point {
        return Qt.point(uv.x, uv.y)
    }

    XrItem {
        id: xritem
        pixelsPerUnit: 20
        manualPixelsPerUnit: true
        automaticHeight: true
        automaticWidth: true
        color: "transparent"

        property Node grabHandle: root

        contentItem: KWinC.WindowThumbnail {
            id: thumbWindow
            property Node parent3d: xritem

            client: root.client
            layer.enabled: false
            layer.effect: MultiEffect {
                blur: 0.1
                blurMax: 8
                blurEnabled: true
            }
        }

        /* XrItem's origin is top level corner. Make the Node above to be at the center of XrItem */
        position: Qt.vector3d(-root.client.width/2/root.ppu, root.client.height/2/root.ppu, 0)
    }
}
