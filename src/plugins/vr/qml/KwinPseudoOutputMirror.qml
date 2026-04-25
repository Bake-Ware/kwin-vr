/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/* This element represents a KWin Output (a monitor) as a CurvedPlane
 * in Free mode. Hosted screen-state windows are added as slots
 * (positioned at output coords) when their client.vr flips false.
 *
 * The VrScreenFrame is a scene-graph child rendering the bezel; it is
 * not part of the slot list and not driven by the abduction system.
 */

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

CurvedPlane {
    id: root
    required property QtObject output

    // Mark so PlaneInteractionManager + window control-tab suppression
    // can recognise pseudomirrors.
    _isPseudomirror: true
    mode: CurvedPlane.Mode.Free
    content: null

    property real ppu: 20

    // Size for SpaceAllocator3D placement
    property size itemSize: Qt.size(frame.frameWidth / ppu, frame.frameHeight / ppu)

    // Bezel grab handle preserved for legacy callers (radial menu, etc.)
    property alias grabHandle: frame.grabHandle

    function uvToWindow2DCoordinates(coords: vector2d): point {
        const geom = root.output.geometry
        return Qt.point(coords.x * geom.width,
                        (1 - coords.y) * geom.height)
    }

    function uvToGlobal2DCoordinates(coords: vector2d): point {
        const geom = root.output.geometry
        return Qt.point(geom.x + coords.x * geom.width,
                        geom.y + (1 - coords.y) * geom.height)
    }

    // Convert a KWin frameGeometry (output coords) to slot.overrides.position
    // for this pseudomirror's Free-mode layout. Z is lifted forward of the
    // bezel by zSurfaceMarginTop to avoid z-fighting with the VrScreenFrame.
    function outputCoordsToSlotPosition(frameGeo) {
        const og = root.output.geometry
        return Qt.vector3d(
                    +(frameGeo.x + frameGeo.width/2 - og.x - og.width/2) / root.ppu,
                    -(frameGeo.y + frameGeo.height/2 - og.y - og.height/2) / root.ppu,
                    KWinVRConfig.zSurfaceMarginTop || 0.5)
    }

    VrScreenFrame {
        id: frame
        property rect outputGeometry: root.output.geometry
        property Node grabHandle: root
        property zMargins itemDepth: ({top: 0.2, bottom: 0})
        frameWidth: frame.outputGeometry.width
        frameHeight: frame.outputGeometry.height
    }
}
