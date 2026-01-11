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

/* This is a KWin window composed from wayland surfaces and subsurfaces without server decorations
 * Each surface is a 3D rectangle. all of them are arranged as a stack by ZStacker.
 */
KwinWaylandSurface3D {
    id: root
    required client
    surface: root.client?.surface ?? null

    /* TODO: maybe move this to C++ ? */
    property QtObject refClient
    onClientChanged: {
        if(this.refClient)
            KwinVrHelpers.windowOffscreenRef(refClient, false)

        this.refClient = this.client

        if(this.refClient)
            KwinVrHelpers.windowOffscreenRef(refClient, true)
    }
    Component.onDestruction: {
        if(refClient) {
            KwinVrHelpers.windowOffscreenRef(refClient, false)
            refClient = null
        }
    }

    Repeater3D {
        id: subSurfaceRepeater
        model: KwinWaylandSurfaceModel {
            id: ssDataModel
            surface: root.surface
        }
        delegate: KwinWaylandSubSurface3DRecursive {
            ppu: root.ppu
            client: root.client
            grabHandle: root.grabHandle
            nextComponent: subSurfaceRepeater.delegate
        }
    }

    property alias itemDepth: rwa.depth
    // onItemDepthChanged: console.log("---> item Depth (main)", itemDepth)
    ZStacker {
        id: rwa
        target: subSurfaceRepeater
        initalMargins.top: root.surfaceDepth
        centerIndex: root.surfaceIndex
        globalOffset: root.zOffsetGlobal
    }

}
