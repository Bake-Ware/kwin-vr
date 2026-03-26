/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Qt.labs.synchronizer

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

ColumnLayout {
    spacing: Kirigami.Units.largeSpacing

    resources: [
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "verticalHeadScrollSpeed"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "horizontalHeadScrollSpeed"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headScrollThreshold"
        }
    ]

    GridLayout {
        columns: 2
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        Controls.Label {
            text: i18nc("@label:slider", "Vertical Speed:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: 0; to: 100; stepSize: 5; decimals: 0
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "verticalHeadScrollSpeed"
            }
        }

        Controls.Label {
            text: i18nc("@label:slider", "Horizontal Speed:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: 0; to: 100; stepSize: 5; decimals: 0
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "horizontalHeadScrollSpeed"
            }
        }

        Controls.Label {
            text: i18nc("@label:slider", "Threshold (degrees):")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: 0.01; to: 1.0; stepSize: 0.01; decimals: 2
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headScrollThreshold"
            }
        }
    }
}