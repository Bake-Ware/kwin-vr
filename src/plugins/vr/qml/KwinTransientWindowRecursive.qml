/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

KwinTransientWindow {
    id: root
    required property int index
    required property QtObject window

    client: root.window
    property int stackingOrder: root.client?.stackingOrder ?? 0
    property real zOffset

    property KwinTransientWindow parentWindow: parent.parent
    property QtObject parentClient: parentWindow?.client

    position: Qt.vector3d(
                  +(client.x + client.width/2 - parentClient.x - parentClient.width/2)/root.ppu,
                  -(client.y + client.height/2 - parentClient.y - parentClient.height/2)/root.ppu,
                  zOffset)

    Binding {
        target: root.client
        property: "vr"
        value: !!(parentWindow.client?.vr)
    }
}
