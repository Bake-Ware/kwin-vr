/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Item {
    id: root

    implicitHeight: innerLayout.implicitHeight

    ColumnLayout {
        id: innerLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Controls.Label {
                text: i18nc("@title:group", "Mouse Button Mappings")
                font.bold: true
            }
            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Here you can select keyboard keys that will act as mouse buttons")
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing

            BindingGroup {
                Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                label: i18nc("@title:group", "Left Button")
                settingName: "leftClickBindings"
                toggleSettingName: "leftClickToggle"
            }

            BindingGroup {
                Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                label: i18nc("@title:group", "Middle Button")
                settingName: "middleClickBindings"
                toggleSettingName: "middleClickToggle"
            }

            BindingGroup {
                Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                label: i18nc("@title:group", "Right Button")
                settingName: "rightClickBindings"
                toggleSettingName: "rightClickToggle"
            }
        }
    }
}
