/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * CurvedWindowContent — renders a KWin window's thumbnail on a
 * CurvedPlaneGeometry. Interactivity routed through VrPicking via the
 * Model's onPick + uvToWindow2DCoordinates.
 *
 * Mirrors the rendering approach in VrHudWindow.qml; intended use is
 * inside a CurvedPlane wrapping a KWin client.
 */

import QtQuick
import QtQuick3D

import org.kde.kwin as KWinC
import org.kde.kwin.vr

Node {
    id: root

    required property QtObject client
    property real curvature: 0.0
    property size sizeWorld: Qt.size(1, 1)
    property Node grabHandle: root
    property alias pickable: model.pickable

    visible: client && !client.minimized && client.opacity > 0
             && (!KwinVrHelpers.screenLocked
                 || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    // Hold an offscreen ref so the thumbnail keeps rendering even when the
    // client is hidden / on another desktop.
    property QtObject refClient
    onClientChanged: {
        if (refClient) KwinVrHelpers.windowOffscreenRef(refClient, false)
        refClient = client
        if (refClient) KwinVrHelpers.windowOffscreenRef(refClient, true)
    }
    Component.onDestruction: {
        if (refClient) {
            KwinVrHelpers.windowOffscreenRef(refClient, false)
            refClient = null
        }
    }

    // Convert pick UV coordinates to window-local 2D coords for KWin input.
    function uvToWindow2DCoordinates(coords: vector2d): point {
        const texSize = winThumbnail.textureSizeLogical
        const frame = winThumbnail.textureFrameRect
        return Qt.point(
            (coords.x * texSize.width) - frame.x,
            ((1 - coords.y) * texSize.height) - frame.y)
    }

    Model {
        id: model
        pickable: true
        depthBias: -100 * KWinVRConfig.depthBiasMultiplier
        property Node grabHandle: root.grabHandle

        geometry: CurvedPlaneGeometry {
            width: root.sizeWorld.width
            height: root.sizeWorld.height
            curvature: root.curvature
        }

        function isPointInRect(px: real, py: real, r: rect): bool {
            return px >= r.x && px <= r.x + r.width
                && py >= r.y && py <= r.y + r.height
        }

        readonly property rect frameUVCoords: {
            const texSize = winThumbnail.textureSizeLogical
            const frame = winThumbnail.textureFrameRect
            if (texSize.width <= 0 || texSize.height <= 0)
                return Qt.rect(0, 0, 1, 1)
            return Qt.rect(
                frame.x / texSize.width,
                1 - (frame.y + frame.height) / texSize.height,
                frame.width / texSize.width,
                frame.height / texSize.height)
        }

        function onPick(pick: pickResult): bool {
            return isPointInRect(pick.uvPosition.x, pick.uvPosition.y, frameUVCoords)
        }

        materials: WindowTextureMaterial {
            texture: Texture {
                sourceItem: KWinC.WindowThumbnail {
                    id: winThumbnail
                    client: root.client
                }
            }
        }
    }
}
