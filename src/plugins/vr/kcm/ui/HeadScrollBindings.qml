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

    property list<string> bindings: kcm.settings.headScrollBindings
    property string lastBinding: bindings.length > 0 ? bindings[bindings.length - 1] : ""

    spacing: Kirigami.Units.smallSpacing

    resources: [
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headScrollBindings"
        }
    ]

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Controls.Label {
            text: i18nc("@title:group", "Head Scroll Activation:")
            font.bold: true
        }
        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Keys or mouse buttons that activate head scroll mode. Hold the key/button and move your head to scroll.")
        }
    }

    // List of bindings
    Repeater {
        id: bindingsRepeater
        model: kcm.settings.headScrollBindings

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            ButtonKeySequenceItem {
                binding: modelData
                onBindingModified: (newBinding) => {
                    let bindings = kcm.settings.headScrollBindings.slice()
                    bindings[index] = newBinding
                    kcm.settings.headScrollBindings = bindings
                }
            }

            Controls.Button {
                icon.name: "list-remove"
                text: ""
                onClicked: {
                    let bindings = kcm.settings.headScrollBindings.slice()
                    bindings.splice(index, 1)
                    kcm.settings.headScrollBindings = bindings
                }
            }
        }
    }

    // Add button
    Controls.Button {
        Layout.alignment: Qt.AlignHCenter
        icon.name: "list-add"
        text: i18nc("@action:button", "Add Binding")
        enabled: root.bindings.length === 0 || (root.lastBinding !== "" && root.lastBinding !== "none")
        onClicked: {
            let bindings = kcm.settings.headScrollBindings.slice()
            bindings.push("")
            kcm.settings.headScrollBindings = bindings
        }
    }
}
