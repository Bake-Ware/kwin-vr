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

KwinWaylandSubSurface3D {
    id: root
    required property int index

    readonly property KwinWaylandSurface3D parentSurface: parent.parent
    required property Component nextComponent//: parent.parent.nextComponent

    position: Qt.vector3d(
                  +(this.surfaceSize.width/2 - this.parentSurface.surfaceSize.width/2 + this.subsurfacePosition.x)/this.ppu,
                  -(this.surfaceSize.height/2 - this.parentSurface.surfaceSize.height/2 + this.subsurfacePosition.y)/this.ppu,
                    zOffset)
    // onPositionChanged: console.log("XXXXXXX surface:", this.surface, "position", position, "index:", index, "parent sur:", this.parentSurface.surfaceIndex)

    windowCoordinates: Qt.point(
                           this.parentSurface.windowCoordinates.x + this.subsurfacePosition.x,
                           this.parentSurface.windowCoordinates.y + this.subsurfacePosition.y)


    Repeater3D {
        id: subSurfaceRepeater
        model: KwinWaylandSurfaceModel {
            id: ssDataModel
            surface: root.surface
        }
        delegate: root.nextComponent
    }

    property alias itemDepth: rwa.depth
    // onItemDepthChanged: console.log("---> item Depth (sub)", itemDepth)
    ZStacker {
        id: rwa
        target: subSurfaceRepeater
        initialMargins: root.surfaceModelDepth
        centerIndex: root.surfaceIndex
        globalOffset: root.zOffsetGlobal
    }
}
