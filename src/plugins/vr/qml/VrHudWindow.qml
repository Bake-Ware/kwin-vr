/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinC
import org.kde.kwin.vr

/*
 * A HUD overlay window rendered on a curved surface matching the HUD plane.
 * Uses CurvedPlaneGeometry + WindowThumbnail for correct curvature wrapping.
 * Pickable for pointer interaction.
 */
Node {
    id: root

    required property QtObject client
    property real ppu: 20
    required property real hudSurfaceW
    required property real hudSurfaceH
    property real hudCurvature: 0

    // For picking/interaction pipeline
    property Node grabHandle: root
    property alias pickable: model.pickable

    // Output geometry for coordinate mapping
    readonly property rect outputGeo: client && client.output
                                      ? client.output.geometry
                                      : Qt.rect(0, 0, KWinVRConfig.width, KWinVRConfig.height)

    // Normalized screen position (-0.5 to +0.5, center = 0)
    readonly property real screenNx: {
        const fg = client.frameGeometry
        return (fg.x + fg.width / 2 - outputGeo.x - outputGeo.width / 2) / outputGeo.width
    }
    readonly property real screenNy: {
        const fg = client.frameGeometry
        return (fg.y + fg.height / 2 - outputGeo.y - outputGeo.height / 2) / outputGeo.height
    }

    // Window world dimensions mapped to HUD
    readonly property real windowWorldW: (client.frameGeometry.width / outputGeo.width) * hudSurfaceW
    readonly property real windowWorldH: (client.frameGeometry.height / outputGeo.height) * hudSurfaceH

    // Place on HUD cylinder
    position: {
        const theta = hudCurvature
        const y = -screenNy * hudSurfaceH

        if (theta < 0.001)
            return Qt.vector3d(screenNx * hudSurfaceW, y, 0.5)

        const t = screenNx + 0.5
        const radius = hudSurfaceW / theta
        const angle = -theta / 2.0 + t * theta
        return Qt.vector3d(
            Math.sin(angle) * radius,
            y,
            -Math.cos(angle) * radius + radius + 0.5)
    }

    // Rotate to match cylinder tangent
    eulerRotation: {
        const theta = hudCurvature
        if (theta < 0.001)
            return Qt.vector3d(0, 0, 0)
        const t = screenNx + 0.5
        const angle = -theta / 2.0 + t * theta
        return Qt.vector3d(0, -angle * 180 / Math.PI, 0)
    }

    visible: client && !client.minimized
             && (!KwinVrHelpers.screenLocked
                 || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    // Keep window rendered offscreen for thumbnail capture
    property QtObject refClient
    onClientChanged: {
        if (refClient)
            KwinVrHelpers.windowOffscreenRef(refClient, false)
        refClient = client
        if (refClient)
            KwinVrHelpers.windowOffscreenRef(refClient, true)
    }
    Component.onDestruction: {
        if (refClient) {
            KwinVrHelpers.windowOffscreenRef(refClient, false)
            refClient = null
        }
    }

    // Convert UV coordinates to window 2D coordinates for pointer input
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
        property Node grabHandle: root

        geometry: CurvedPlaneGeometry {
            width: root.windowWorldW
            height: root.windowWorldH
            curvature: root.hudCurvature < 0.001
                       ? 0
                       : root.hudCurvature * root.windowWorldW / root.hudSurfaceW
        }

        // Accept pick only within window frame (not shadow area)
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
