/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/*
 * Pseudomirror — a CurvedPlane representing a KWin Output (monitor).
 *
 * Mode: Free, with stackChildren=true so overlapping screen-state
 * windows get an automatic +Z lift. intrinsicCurvature=0 so the
 * pseudomirror itself and its hosted children render flat.
 *
 * Hosted children are KwinApplicationWindow CurvedPlanes registered
 * as our slots when client.vr === false. Their slot.overrides.position
 * is driven from the window's frameGeometry by KwinApplicationWindow.
 */
CurvedPlane {
    id: root
    required property QtObject output

    mode: CurvedPlane.Mode.Free
    stackChildren: true
    _isPseudomirror: true
    // Pseudomirror's curvature drives every child via the abductor curvature
    // push: wallpaper, screen-state windows, and any other slot child all
    // inherit it. Free-floating VR windows already pick up the same value
    // through their own intrinsicCurvature.
    intrinsicCurvature: KWinVRConfig.defaultWindowCurvature || 0.0
    intrinsicSize: Qt.size(frame.frameWidth / root.ppu, frame.frameHeight / root.ppu)

    property alias ppu: frame.ppu

    // Legacy alias kept for callers that read `grabHandle` to find the
    // ray-pick target. Pseudomirrors are themselves the grab handle.
    readonly property Node grabHandle: root

    // Size in 3D units for SpaceAllocator3D.
    readonly property size itemSize: root.intrinsicSize

    function uvToWindow2DCoordinates(coords: vector2d): point {
        const geom = root.output.geometry
        return Qt.point(
                    (coords.x * geom.width),
                    (1 - coords.y) * geom.height)
    }

    function uvToGlobal2DCoordinates(coords: vector2d): point {
        const geom = root.output.geometry
        return Qt.point(
                    geom.x + (coords.x * geom.width),
                    geom.y + (1 - coords.y) * geom.height)
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
