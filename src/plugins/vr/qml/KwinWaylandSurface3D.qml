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

/* This is a wayland surface as a 3D rectangle model */
Node {
    id: root
    /* KWin::SurfaceInterface */
    required property QtObject surface

    property real ppu: 20
    property alias grabHandle: model.grabHandle
    property alias pickable: model.pickable
    readonly property Model surfaceModel: model
    property size surfaceSize: this.surface ? this.surface.size : Qt.size(0,0)

    /* Thickness of this surface */
    property real surfaceDepth: (surfaceSize.width > 1 && surfaceSize.height > 1) && model.pickable ? 1 : 0
    /* An index in a stack. Will be set by zStacker */
    property real zOffset: 0
    /* Global Z offset including parent offsets. Will be set by ZStacker */
    property real zOffsetGlobal: 0

    /* 2D coordinates of a top left point of this surface inside a window */
    property point windowCoordinates: Qt.point(0,0)

    /* A window this surface belongs to */
    property QtObject client
    visible: this.client && !this.client.minimized && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    function uvToWindow2DCoordinates(coords: vector2d): point {
        return Qt.point(
                    (coords.x * root.surfaceSize.width) + root.windowCoordinates.x,
                    ((1 - coords.y) * root.surfaceSize.height) + root.windowCoordinates.y)
    }

    /* This property reflects a position in a subsurface stack.
     * Stack starts with 0, so if there is one subsurface below this surface then this number will be increased by 1.
     */
    property int surfaceIndex: KwinVrHelpers.surfaceIndex(root.surface)
    Connections {
        target: root.surface
        function onChildSubSurfacesChanged() {
            root.surfaceIndex = KwinVrHelpers.surfaceIndex(root.surface);
        }
    }
    Connections {
        target: root
        function onSurfaceChanged() {
            root.surfaceIndex = KwinVrHelpers.surfaceIndex(root.surface);
        }
    }

    Texture {
        id: primaryTexture
        sourceItem: KwinWaylandSurface {
            id: kws
            surface: root.surface
        }
        positionU: kws.uvCoords.x
        scaleU: kws.uvCoords.y
        positionV: kws.uvCoords.z
        scaleV: kws.uvCoords.w
    }

    Component {
        id: rgbMaterial
        WindowTextureMaterial {
            texture: primaryTexture
            isOpaque: kws.fullyOpaque
        }
    }

    Component {
        id: yuvMaterial
        YuvMaterial {
            yuvToRgb: kws.yuvMatrix
            yTexture: TextureInput {
                texture: primaryTexture
            }
            uvTexture: TextureInput {
                texture: Texture {
                    sourceItem: kws.uvTexture
                }
            }
        }
    }

    Loader {
        id: materialLoader
        active: true
        sourceComponent: kws.uvTexture ? yuvMaterial : rgbMaterial
    }

    Model {
        id: model
        property Node grabHandle: root
        pickable: (root.surfaceSize.width > 0) && (root.surfaceSize.height > 0) && root.visible
        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier

        function isPointInsideRect(r: rect, p: point): bool {
            return p.x >= r.left && p.x <= r.right && p.y >= r.top && p.y <= r.bottom
        }

        function onPick(pick: pickResult): bool {
            const winGeo = KwinVrHelpers.windowGeometry(root.client)
            if(winGeo.width <= 1 || winGeo.height <= 1 ) {
                return true
            }

            const coords = root.uvToWindow2DCoordinates(pick.uvPosition)
            /* Allow picking only if the point is inside window geometry.
             * (set by xdg_surface::set_window_geometry) */

            //TODO: we can know in advance when the surface will be always inside window geometry */
            return isPointInsideRect(winGeo, coords);
        }

        source: "#Rectangle"
        // materials: kws.uvTexture ? yuvMaterial : rgbMaterial
        materials: materialLoader.item

        scale: Qt.vector3d(root.surfaceSize.width/100/root.ppu,
                           root.surfaceSize.height/100/root.ppu,
                           root.surfaceDepth/100)
    }
}
