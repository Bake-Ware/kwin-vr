/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.NavigationTabBar {
            id: tabBar
            Layout.fillWidth: true

            actions: [
                Kirigami.Action {
                    text: i18nc("@title:tab", "General")
                    icon.name: "configure"
                    onTriggered: stackLayout.currentIndex = 0
                    checked: stackLayout.currentIndex === 0
                },
                Kirigami.Action {
                    text: i18nc("@title:tab", "Virtual Display")
                    icon.name: "video-display"
                    onTriggered: stackLayout.currentIndex = 1
                    checked: stackLayout.currentIndex === 1
                },
                Kirigami.Action {
                    text: i18nc("@title:tab", "Follow Mode")
                    icon.name: "transform-move"
                    onTriggered: stackLayout.currentIndex = 2
                    checked: stackLayout.currentIndex === 2
                },
                Kirigami.Action {
                    text: i18nc("@title:tab", "Input")
                    icon.name: "input-keyboard"
                    onTriggered: stackLayout.currentIndex = 3
                    checked: stackLayout.currentIndex === 3
                },
                Kirigami.Action {
                    text: i18nc("@title:tab", "Advanced")
                    icon.name: "preferences-other"
                    onTriggered: stackLayout.currentIndex = 4
                    checked: stackLayout.currentIndex === 4
                }
            ]
        }

        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.preferredHeight: children[currentIndex].implicitHeight

            GeneralSetup {}

            VirtualDisplaySetup {}

            FollowModeSetup {}

            InputSetup {}

            AdvancedSetup {}
        }
    }
}
