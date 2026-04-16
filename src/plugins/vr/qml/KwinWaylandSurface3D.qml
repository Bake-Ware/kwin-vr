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
    property zMargins surfaceModelDepth: ({
                                              top: model.pickable ? KWinVRConfig.zSurfaceMarginTop : 0,
                                              bottom: model.pickable ? KWinVRConfig.zSurfaceMarginBottom : 0
                                          })
    /* An index in a stack. Will be set by zStacker */
    property real zOffset: 0
    /* Global Z offset including parent offsets. Will be set by ZStacker */
    property real zOffsetGlobal: 0

    /* 2D coordinates of a top left point of this surface inside a window */
    property point windowCoordinates: Qt.point(0,0)

    /* A window this surface belongs to */
    property QtObject client
    visible: this.client && !this.client.minimized && this.client.opacity > 0 && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)
    readonly property rect bufferGeo: root.client?.bufferGeometry ?? Qt.rect(0, 0, 0, 0)
    readonly property rect clientGeo: root.client?.clientGeometry ?? Qt.rect(0, 0, 0, 0)

    function uvToWindow2DCoordinates(coords: vector2d): point {
        return Qt.point(
                    (coords.x * root.surfaceSize.width) + root.windowCoordinates.x,
                    ((1 - coords.y) * root.surfaceSize.height) + root.windowCoordinates.y)
    }

    function rectContainsRect(outer: rect, inner: rect): bool {
        return inner.left >= outer.left
                && inner.right <= outer.right
                && inner.top >= outer.top
                && inner.bottom <= outer.bottom
    }

    readonly property rect bufferLocalWindowRect: Qt.rect(root.clientGeo.x - root.bufferGeo.x,
                                                          root.clientGeo.y - root.bufferGeo.y,
                                                          root.clientGeo.width,
                                                          root.clientGeo.height)

    readonly property rect surfaceRectInBuffer: Qt.rect(root.windowCoordinates.x,
                                                        root.windowCoordinates.y,
                                                        root.surfaceSize.width,
                                                        root.surfaceSize.height)

    readonly property bool alwaysInsideGeometry: rectContainsRect(root.bufferLocalWindowRect,
                                                                   root.surfaceRectInBuffer)

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

    // Curved geometry for work-surface-attached windows. The grab handle
    // (typically the owning KwinApplicationWindow) carries regionKind and
    // regionRadius so each surface in the window tree can pick the right mesh.
    readonly property int regionKind: (model.grabHandle && model.grabHandle.regionKind !== undefined)
                                      ? model.grabHandle.regionKind
                                      : WorkSurfaceRegion.FlatRect
    readonly property real regionRadius: (model.grabHandle && model.grabHandle.regionRadius !== undefined)
                                         ? model.grabHandle.regionRadius
                                         : 30

    readonly property real _surfWorldWidth: root.surfaceSize.width / Math.max(root.ppu, 0.0001)
    readonly property real _surfWorldHeight: root.surfaceSize.height / Math.max(root.ppu, 0.0001)

    CylinderBodyGeometry {
        id: _cylGeom
        radius: root.regionRadius
        arcAngle: Math.min(2 * Math.PI,
                           root._surfWorldWidth / Math.max(root.regionRadius, 0.001))
        height: root._surfWorldHeight
        segments: 32
    }

    SpherePatchGeometry {
        id: _sphGeom
        radius: root.regionRadius
        widthAngle: Math.min(Math.PI,
                             root._surfWorldWidth / Math.max(root.regionRadius, 0.001))
        heightAngle: Math.min(Math.PI,
                              root._surfWorldHeight / Math.max(root.regionRadius, 0.001))
        columns: 24
        rows: 16
    }

    Model {
        id: model
        property Node grabHandle: root
        pickable: (root.surfaceSize.width > 0) && (root.surfaceSize.height > 0) && root.visible
        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier

        function isPointInsideRect(r: rect, p: point): bool {
            return p.x >= r.left && p.x <= r.right && p.y >= r.top && p.y <= r.bottom
        }

        function onPickAlways(_pick: pickResult): bool {
            return true
        }

        readonly property bool useGeometryPick: !root.alwaysInsideGeometry
                                               && root.clientGeo.width > 1
                                               && root.clientGeo.height > 1

        function onPickReal(pick: pickResult): bool {
            const coords = root.uvToWindow2DCoordinates(pick.uvPosition)
            const globalCoords = Qt.point(root.bufferGeo.x + coords.x, root.bufferGeo.y + coords.y)
            /* Allow picking only if the point is inside client geometry.
             * (client geometry size reflects xdg_surface::set_window_geometry). */
            return isPointInsideRect(root.clientGeo, globalCoords)
        }

        readonly property var onPick: useGeometryPick ? onPickReal : onPickAlways

        // Flat regions keep the stock #Rectangle mesh (scaled to surface size).
        // Curved regions swap in a procedural mesh with world-unit vertices.
        source: root.regionKind === WorkSurfaceRegion.FlatRect ? "#Rectangle" : ""
        geometry: {
            switch (root.regionKind) {
            case WorkSurfaceRegion.CylinderBody: return _cylGeom
            case WorkSurfaceRegion.SpherePatch: return _sphGeom
            default: return null
            }
        }
        materials: materialLoader.item

        scale: root.regionKind === WorkSurfaceRegion.FlatRect
               ? Qt.vector3d(root.surfaceSize.width / 100 / root.ppu,
                             root.surfaceSize.height / 100 / root.ppu,
                             0.01)
               : Qt.vector3d(1, 1, 1)
    }
}
