/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    required property int logicalWidth
    required property int logicalHeight
    required property int scale
    required property int ppu

    readonly property real aspectRatio: logicalWidth / logicalHeight

    // Outer bezel
    color: "#2a2a2a"
    border.color: "#1a1a1a"
    border.width: 2
    radius: 8

    // Inner screen
    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.highlightColor
        border.width: 1
        radius: 4

        // Display info in center
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: (root.logicalWidth * root.scale) + " x " + (root.logicalHeight * root.scale)
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@item:valuesuffix", "pixels")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@label", "%1 x %2 cm", (root.logicalWidth / root.ppu).toFixed(1), (root.logicalHeight / root.ppu).toFixed(1))
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
            }
        }
    }
}
