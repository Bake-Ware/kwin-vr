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

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: [
            { label: i18nc("@label", "Button 1 Press"), setting: "Button1Pressed" },
            { label: i18nc("@label", "Button 1 Touch"), setting: "Button1Touched" },
            { label: i18nc("@label", "Button 2 Press"), setting: "Button2Pressed" },
            { label: i18nc("@label", "Button 2 Touch"), setting: "Button2Touched" },
            { label: i18nc("@label", "Menu Button Press"), setting: "ButtonMenuPressed" },
            { label: i18nc("@label", "Menu Button Touch"), setting: "ButtonMenuTouched" },
            { label: i18nc("@label", "System Button Press"), setting: "ButtonSystemPressed" },
            { label: i18nc("@label", "System Button Touch"), setting: "ButtonSystemTouched" },
            { label: i18nc("@label", "Trigger Touch"), setting: "TriggerTouched" },
            { label: i18nc("@label", "Thumbstick Press"), setting: "ThumbstickPressed" },
            { label: i18nc("@label", "Thumbstick Touch"), setting: "ThumbstickTouched" },
            { label: i18nc("@label", "Thumbrest Touch"), setting: "ThumbrestTouched" },
            { label: i18nc("@label", "Trackpad Touch"), setting: "TrackpadTouched" },
            { label: i18nc("@label", "Trackpad Press"), setting: "TrackpadPressed" },
            { label: i18nc("@label", "Index Finger Pinch"), setting: "IndexFingerPinch" },
            { label: i18nc("@label", "Middle Finger Pinch"), setting: "MiddleFingerPinch" },
            { label: i18nc("@label", "Ring Finger Pinch"), setting: "RingFingerPinch" },
            { label: i18nc("@label", "Little Finger Pinch"), setting: "LittleFingerPinch" },
            { label: i18nc("@label", "Hand Menu Press"), setting: "HandTrackingMenuPress" }
        ]

        delegate: ColumnLayout {
            id: delegateRoot
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            readonly property string fullSettingName: root.handPrefix + modelData.setting

            KCMUtils.SettingStateBinding {
                configObject: kcm.settings
                settingName: delegateRoot.fullSettingName
            }

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

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: index < 18
            }
        }
    }
}
