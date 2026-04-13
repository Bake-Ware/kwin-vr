/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin.vr

/* A full 3D KWin Window with decorations.
 *
 * This element contains decorations model and one or multiple window surfaces, arrange as a stack.
 */
Node {
    id: root
    required property QtObject client
    visible: root.client && !root.client.minimized

    property real ppu: 20
    property Node grabHandle: root
    property zMargins itemDepth
    property real zOffsetGlobal: 0

    KwinDecorations3D {
        id: deco3d
        client: root.client
        grabHandle: root.grabHandle
        ppu: root.ppu
        zOffsetGlobal: root.zOffsetGlobal
    }

    property vector3d innerWindowPosition: {
        const frameGeo = root.client.frameGeometry
        const bufferGeo = root.client.bufferGeometry

        return Qt.vector3d(
                    ((bufferGeo.x + bufferGeo.width / 2) - (frameGeo.x + frameGeo.width / 2)) / root.ppu,
                    -((bufferGeo.y + bufferGeo.height / 2) - (frameGeo.y + frameGeo.height / 2)) / root.ppu,
                    0)
    }

    Component {
        id: surfacedWindow
        KwinSurfacedWindow3D {
            ppu: root.ppu
            grabHandle: root.grabHandle
            client: root.client
            position: root.innerWindowPosition
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Component {
        id: internalWindow
        KwinInternalWindow3D {
            ppu: root.ppu
            grabHandle: root.grabHandle
            client: root.client
            position: root.innerWindowPosition
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Loader3D {
        id: winLoader
        active: root.client
        sourceComponent: KwinVrHelpers.windowIsInternal(root.client) ? internalWindow : surfacedWindow

        /* Copy internal or surfaced window depth (decorations have no depth currently) */
        Binding {
            target: root
            property: "itemDepth"
            value: winLoader.item.itemDepth
            when: winLoader.item
        }
    }
}
