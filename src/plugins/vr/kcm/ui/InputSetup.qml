/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

Item {
    id: root

    implicitHeight: innerLayout.implicitHeight

    ColumnLayout {
        id: innerLayout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        Controls.TabBar {
            id: inputTabBar
            Layout.alignment: Qt.AlignHCenter
            currentIndex: inputStackLayout.currentIndex
            onCurrentIndexChanged: inputStackLayout.currentIndex = currentIndex

            Controls.TabButton {
                text: i18nc("@title:tab", "Headgaze")
                icon.name: "view-visible"
            }
            Controls.TabButton {
                text: i18nc("@title:tab", "Head Scroll")
                icon.name: "transform-move-vertical"
            }
            Controls.TabButton {
                text: i18nc("@title:tab", "Mouse Bindings")
                icon.name: "input-mouse"
            }
            Controls.TabButton {
                text: i18nc("@title:tab", "VR Controller")
                icon.name: "input-gamepad"
            }
        }

        StackLayout {
            id: inputStackLayout
            Layout.fillWidth: true

            HeadgazeSetup {}

            HeadScrollSetup {}

            KeysToMouseButtonBindings {}

            VrControllerBindings {}
        }
    }
}
