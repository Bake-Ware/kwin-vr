/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

ColumnLayout {
    id: root

    property string handPrefix: "left"

    spacing: Kirigami.Units.largeSpacing

    Repeater {
        model: [
            { label: i18nc("@label:slider", "Horizontal Speed:"), setting: "ThumbstickX" },
            { label: i18nc("@label:slider", "Vertical Speed:"), setting: "ThumbstickY" }
        ]

        delegate: ColumnLayout {
            Layout.fillWidth: true

            readonly property string fullSetting: root.handPrefix + modelData.setting

            KCMUtils.SettingStateBinding {
                configObject: kcm.settings
                settingName: parent.fullSetting
            }

            ValueSlider {
                Layout.fillWidth: true
                label: modelData.label
                value: kcm.settings[parent.fullSetting]
                onValueChanged: kcm.settings[parent.fullSetting] = value
            }
        }
    }
}
