/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.kcmutils as KCMUtils

ColumnLayout {
    id: root

    property string label
    property string settingName
    property string toolTipText
    property string toggleSettingName: ""

    property list<string> bindings: kcm.settings[root.settingName]
    property string lastBinding: bindings.length > 0 ? bindings[bindings.length - 1] : ""

    spacing: Kirigami.Units.smallSpacing

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: root.settingName
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: root.toggleSettingName
        enabled: root.toggleSettingName !== ""
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Controls.Label {
            text: root.label
            font.bold: true
        }
    }

    Repeater {
        id: repeater
        model: kcm.settings[root.settingName]

        RowLayout {
            id: delegateRoot
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            required property string modelData
            required property int index

            KQuickControls.KeySequenceItem {
                Layout.fillWidth: true
                multiKeyShortcutsAllowed: false
                keySequence: delegateRoot.modelData === "none" ? "" : delegateRoot.modelData
                patterns: KQuickControls.ShortcutPattern.Key | KQuickControls.ShortcutPattern.Modifier

                onKeySequenceModified: {
                     var list = kcm.settings[root.settingName].slice()
                     let seq = keySequence.toString()
                     list[delegateRoot.index] = (seq === "") ? "none" : seq
                     kcm.settings[root.settingName] = list
                }
            }

            Controls.Button {
                icon.name: "list-remove"
                text: ""
                onClicked: {
                    var list = kcm.settings[root.settingName].slice()
                    list.splice(delegateRoot.index, 1)
                    kcm.settings[root.settingName] = list
                }
            }
        }
    }

    Controls.Button {
        Layout.alignment: Qt.AlignHCenter
        icon.name: "list-add"
        text: i18nc("@action:button", "Add Binding")
        enabled: root.bindings.length === 0 || (root.lastBinding !== "none" && root.lastBinding !== "")
        onClicked: {
            var list = kcm.settings[root.settingName].slice()
            list.push("none")
            kcm.settings[root.settingName] = list
        }
    }

    Controls.CheckBox {
        visible: root.toggleSettingName !== ""
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@option:check", "Toggle")
        checked: root.toggleSettingName !== "" && kcm.settings[root.toggleSettingName]
        onToggled: {
            if (root.toggleSettingName !== "")
                kcm.settings[root.toggleSettingName] = checked
        }
    }
}
