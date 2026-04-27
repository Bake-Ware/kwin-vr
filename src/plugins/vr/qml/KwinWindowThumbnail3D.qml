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

import org.kde.kwin as KWinC
import org.kde.kwin.vr

/* This is a single and full KWin window as a 3D rectangle.
 * It is rendered by KWin's WindowThumbnail, so it contains
 * all surfaces, shadows and decotations. Effects are also applied.
 *
 * WindowThumbnail uses KWin's native renderer to draw a window to the texture first (offscreen rendering),
 * So it is bad for performance, but the result is the same as ordinary 2D windows.
 *
 * It is similar to KwinWindowThumbnailXrItem, but the window's texture is loaded into Model, instead of being drawn to
 * Qt Quick 2D scene. KWinC.WindowThumbnail acts as a texture provider here.
 *
 */
Node {
    id: root

    // Walks the Qt scene-graph parent chain to find the nearest
    // CurvedPlane ancestor (identified by having a planeId + an
    // effectiveCurvature). Falls back to defaultWindowCurvature.
    readonly property real _ancestorPlaneCurvature: {
        let n = root.parent
        while (n) {
            if (n.planeId !== undefined && n.effectiveCurvature !== undefined) {
                return n.effectiveCurvature
            }
            n = n.parent
        }
        return KWinVRConfig.defaultWindowCurvature || 0.0
    }

    required property QtObject client

    property alias grabHandle: model.grabHandle
    property real ppu: 20
    property bool eff: false

    property alias windowThumbnail: winT
    property alias pickable: model.pickable

    property zMargins itemDepth: ({
                                      top: root.visible ? KWinVRConfig.zWindowMarginTop : 0,
                                      bottom: root.visible ? KWinVRConfig.zWindowMarginBottom : 0
                                  })
    property real zOffsetGlobal: 0

    readonly property Model window3dModel: model

    visible: this.client && !this.client.minimized && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    function uvToWindow2DCoordinates(coords: vector2d): point {
        const texSize = winT.textureSizeLogical
        const frame = winT.textureFrameRect

        return Qt.point(
                    (coords.x * texSize.width) - frame.x,
                    ((1 - coords.y) * texSize.height) - frame.y)
    }

    Model {
        id: model
        visible: root.visible
        pickable: this.visible
        property Node grabHandle: root

        function isPointInRect(pointX: real, pointY: real, rect: rect): bool {
            return pointX >= rect.x &&
                   pointX <= rect.x + rect.width &&
                   pointY >= rect.y &&
                   pointY <= rect.y + rect.height;
        }

        function onPick(pick: pickResult): bool {
            /* Do not allow picking if the point is in shadow area */
            const ret = isPointInRect(pick.uvPosition.x, pick.uvPosition.y, frameUVCoords);
            return ret;
        }

        property rect frameUVCoords: {
            const texSize = winT.textureSizeLogical
            const frame = winT.textureFrameRect

            return Qt.rect(
                        frame.x / texSize.width,
                        1 - (frame.y + frame.height) / texSize.height,
                        frame.width / texSize.width,
                        frame.height / texSize.height
                        )
        }

        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier
        geometry: CurvedPlaneGeometry {
            width: winT.textureSizeLogical.width / root.ppu
            height: winT.textureSizeLogical.height / root.ppu
            // Curvature inherits from the nearest CurvedPlane ancestor.
            // For a top-level free VR window: its own plane's curvature
            // (= KWinVRConfig.defaultWindowCurvature). For a hosted
            // (screen-state) window: the pseudomirror's curvature (= 0).
            // For a transient inside a window: the window's curvature.
            curvature: root._ancestorPlaneCurvature
        }
        materials: WindowTextureMaterial {
            id: material
            texture: Texture {
                sourceItem: KWinC.WindowThumbnail {
                    id: winT
                    client: root.client
                }
            }
        }

        position: {
            const texSize = winT.textureSizeLogical
            const frame = winT.textureFrameRect

            return Qt.vector3d(
                        +(((texSize.width - frame.width)/2) - frame.x)/root.ppu,
                        -(((texSize.height - frame.height)/2) - frame.y)/root.ppu,
                        0)
        }
    }
}
