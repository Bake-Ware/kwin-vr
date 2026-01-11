/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    spacing: Kirigami.Units.largeSpacing

    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title", "Controller Mappings")
        font.bold: true
    }

    // Left / Right Controller labels
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 2

        Controls.Label {
            text: i18nc("@title:group", "Left Controller")
            font.bold: true
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.1
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Controls.Label {
            text: i18nc("@title:group", "Right Controller")
            font.bold: true
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.1
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Analog section
    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title:group", "Analog")
        font.bold: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 2

        VrControllerAnalogBindings {
            handPrefix: "left"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }

        VrControllerAnalogBindings {
            handPrefix: "right"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // Thumbstick Scroll section
    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title:group", "Thumbstick Scroll")
        font.bold: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 2

        VrControllerThumbstickScroll {
            handPrefix: "left"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }

        VrControllerThumbstickScroll {
            handPrefix: "right"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // Buttons section
    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title:group", "Buttons")
        font.bold: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 2

        VrControllerSimpleBindings {
            handPrefix: "left"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }

        VrControllerSimpleBindings {
            handPrefix: "right"
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
        }
    }
}
