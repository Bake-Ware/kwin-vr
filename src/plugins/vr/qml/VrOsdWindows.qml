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

/* Displays OSD windows only
 * (windows at the center of the screen when you change keyobard layout or change audio volume level)
*/
Repeater3D {
    id: root
    property real ppu: 20
    property alias windowModel: osdFilter.windowModel
    model: OsdWindowFilter {
        id: osdFilter
    }
    delegate: KwinSurfacedWindow3D {
        ppu: root.ppu
        required property QtObject window
        client: window
        pickable: false
        zOffsetGlobal: 100 //to make it closer
        visible: (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)
    }
}
