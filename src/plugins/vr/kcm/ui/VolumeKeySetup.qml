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

Item {
    id: root

    implicitHeight: innerLayout.implicitHeight

    resources: [
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "volumeClickEnabled"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "volumeClickComboTimeout"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "volUpClickButton"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "volDownClickButton"
        }
    ]

    ColumnLayout {
        id: innerLayout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Controls.Label {
                text: i18nc("@title:group", "Volume Key Click Mode")
                font.bold: true
            }
            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Use volume keys as mouse click toggles. Press Vol+ then Vol- (or vice versa) within the combo timeout to switch between volume and click modes. In click mode, each volume key press toggles a mouse button down/up.")
            }
        }

        Controls.CheckBox {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@option:check", "Enable volume key click mode")
            checked: kcm.settings.volumeClickEnabled
            onToggled: kcm.settings.volumeClickEnabled = checked
        }

        GridLayout {
            columns: 2
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            enabled: kcm.settings.volumeClickEnabled

            Controls.Label {
                text: i18nc("@label:slider", "Combo Timeout (ms):")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            ValueSlider {
                Layout.fillWidth: true
                label: ""
                labelWidth: 0
                from: 200; to: 2000; stepSize: 50; decimals: 0
                Synchronizer on value {
                    sourceObject: kcm.settings
                    sourceProperty: "volumeClickComboTimeout"
                }
            }

            Controls.Label {
                text: i18nc("@label:listbox", "Volume Up → Mouse Button:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                id: volUpCombo
                Layout.fillWidth: true
                model: [
                    { text: i18nc("@item:inlistbox", "Left"), value: "left" },
                    { text: i18nc("@item:inlistbox", "Right"), value: "right" },
                    { text: i18nc("@item:inlistbox", "Middle"), value: "middle" }
                ]
                textRole: "text"
                valueRole: "value"
                currentIndex: indexOfValue(kcm.settings.volUpClickButton)
                onActivated: kcm.settings.volUpClickButton = currentValue
            }

            Controls.Label {
                text: i18nc("@label:listbox", "Volume Down → Mouse Button:")
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            Controls.ComboBox {
                id: volDownCombo
                Layout.fillWidth: true
                model: [
                    { text: i18nc("@item:inlistbox", "Left"), value: "left" },
                    { text: i18nc("@item:inlistbox", "Right"), value: "right" },
                    { text: i18nc("@item:inlistbox", "Middle"), value: "middle" }
                ]
                textRole: "text"
                valueRole: "value"
                currentIndex: indexOfValue(kcm.settings.volDownClickButton)
                onActivated: kcm.settings.volDownClickButton = currentValue
            }
        }
    }
}
