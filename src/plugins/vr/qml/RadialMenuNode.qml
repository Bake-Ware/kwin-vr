/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

Node {
    id: root
    property alias grabHandle: wrv.grabHandle
    property real ppu: 20
    property real extraScale: 3

    property alias buttonLabels: radialMenu.buttonLabels
    property alias buttonEnabled: radialMenu.buttonEnabled
    property alias menuItems: radialMenu.menuItems
    signal buttonClicked(int index)
    signal actionTriggered(string action)
    signal centerButtonClicked()
    signal closed()

    function close() {
        radialMenu.close()
    }

    VRWindow {
        id: wrv
        property Node grabHandle: root
        scale: Qt.vector3d(radialMenu.width/100/root.ppu/root.extraScale, radialMenu.height/100/root.ppu/root.extraScale, 1)
        //why without extra scale it works??
        position: Qt.vector3d(-radialMenu.width/2/root.ppu, radialMenu.height/2/root.ppu, 0.1)
        RadialMenu {
            property Node parent3d: wrv
            id: radialMenu
            onButtonClicked: (index) => root.buttonClicked(index)
            onActionTriggered: (action) => root.actionTriggered(action)
            onCenterButtonClicked: root.centerButtonClicked()
            onClosed: root.closed()
        }
    }
}
