/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs

import org.kde.kirigami as Kirigami

Controls.Button {
    id: root

    property color selectedColor
    property string dialogTitle: i18nc("@title:window", "Select Color")

    implicitWidth: Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 1.5

    background: Rectangle {
        // Checkerboard pattern for transparency visualization
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                var size = 6
                for (var x = 0; x < width; x += size) {
                    for (var y = 0; y < height; y += size) {
                        ctx.fillStyle = ((x / size + y / size) % 2 === 0) ? "#cccccc" : "#ffffff"
                        ctx.fillRect(x, y, size, size)
                    }
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: root.selectedColor
        }
        border.color: Kirigami.Theme.textColor
        border.width: 1
        radius: 3
    }

    onClicked: colorDialog.open()

    ColorDialog {
        id: colorDialog
        title: root.dialogTitle
        selectedColor: root.selectedColor
        options: ColorDialog.ShowAlphaChannel
        onAccepted: root.selectedColor = selectedColor
    }
}
