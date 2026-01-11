/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

ColumnLayout {
    id: root

    property string handPrefix: "left"

    spacing: Kirigami.Units.largeSpacing

    Repeater {
        model: [
            { label: i18nc("@label", "Squeeze"), setting: "SqueezePressed", thresholdSetting: "SqueezeValue" },
            { label: i18nc("@label", "Trigger"), setting: "TriggerPressed", thresholdSetting: "TriggerValue" }
        ]

        delegate: ColumnLayout {
            id: delegateRoot
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            readonly property string fullSettingName: root.handPrefix + modelData.setting
            readonly property string thresholdSettingName: root.handPrefix + modelData.thresholdSetting

            KCMUtils.SettingStateBinding {
                configObject: kcm.settings
                settingName: delegateRoot.fullSettingName
            }

            KCMUtils.SettingStateBinding {
                configObject: kcm.settings
                settingName: delegateRoot.thresholdSettingName
            }

            // Label and key binding
            RowLayout {
                Layout.fillWidth: true

                Controls.Label {
                    text: modelData.label
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                }

                ButtonKeySequenceItem {
                    Layout.fillWidth: true
                    binding: kcm.settings[delegateRoot.fullSettingName]
                    onBindingModified: (newBinding) => {
                        kcm.settings[delegateRoot.fullSettingName] = newBinding
                    }
                }
            }

            ValueSlider {
                Layout.fillWidth: true
                label: i18nc("@label:slider", "Threshold:")
                value: kcm.settings[delegateRoot.thresholdSettingName]
                onValueChanged: kcm.settings[delegateRoot.thresholdSettingName] = value
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: index < 1
            }
        }
    }
}
