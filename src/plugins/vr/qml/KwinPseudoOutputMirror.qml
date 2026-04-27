/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

/* This element represent a Kwin Output (a monitor, basically)
 * All children of this element are sorted by VolumetricStacker.
 * the VrScreenFrame is always at the bottom.
 *
 * children should have stackingOrder property to be sorted
 */
Node {
    id: root
    required property QtObject output

    property alias grabHandle: frame.grabHandle
    property alias ppu: frame.ppu

    // Size in 3D units for SpaceAllocator3D
    property size itemSize: Qt.size(frame.frameWidth / ppu, frame.frameHeight / ppu)

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

    property alias itemDepth: stacker.depth
    VolumetricStacker {
        id: stacker
        target: root
        childIndexPropertyName: "stackingOrder"
        initialMargins: frame.itemDepth
        globalOffset: 0
    }
}
