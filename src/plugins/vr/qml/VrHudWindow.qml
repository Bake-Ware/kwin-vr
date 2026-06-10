/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinC
import org.kde.kwin.vr

import "HudPlacementLogic.js" as HudPlacement

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

    // Transient-chain depth: 0 = root HUD window, 1 = its popup/menu,
    // 2 = submenu… (chains are fixed at map time, capped like
    // HudWindowFilter's ancestor walk).
    readonly property int transientDepth: {
        let d = 0
        let a = client ? client.transientFor : null
        while (a && d < 10) { d++; a = a.transientFor }
        return d
    }

    // Place on HUD cylinder, lifted one radial step per transient level so
    // popups/menus never z-fight the window they belong to (#17). Math in
    // HudPlacementLogic.js (pure, qmltest-pinned).
    readonly property var hudPose: HudPlacement.placeOnHud(
        screenNx, screenNy, hudSurfaceW, hudSurfaceH, hudCurvature,
        HudPlacement.surfaceLift(transientDepth))

    position: Qt.vector3d(hudPose.x, hudPose.y, hudPose.z)

    // Rotate to match cylinder tangent
    eulerRotation: Qt.vector3d(0, hudPose.yawDeg, 0)

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
