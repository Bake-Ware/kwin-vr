/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

RowLayout {
    id: root

    property string binding: "MouseMiddle"

    readonly property bool isMouseBinding: binding.startsWith("Mouse")

    signal bindingModified(string newBinding)

    spacing: Kirigami.Units.smallSpacing

    // Toggle: Key / Button
    Controls.Switch {
        id: modeSwitch
        checked: root.isMouseBinding
        onClicked: {
            if (checked) {
                // Switching to mouse mode
                root.binding = "MouseMiddle"
                root.bindingModified(root.binding)
            } else {
                // Switching to key mode - clear binding
                root.binding = ""
                root.bindingModified(root.binding)
            }
        }
    }

    Controls.Label {
        text: modeSwitch.checked ? i18nc("@option:radio", "Button") : i18nc("@option:radio", "Key")
        Layout.preferredWidth: 45
    }

    // KeySequenceItem (visible when Key mode)
    KQuickControls.KeySequenceItem {
        id: keySequenceItem
        visible: !root.isMouseBinding
        Layout.fillWidth: true
        keySequence: root.isMouseBinding ? "" : root.binding
        multiKeyShortcutsAllowed: false
        patterns: KQuickControls.ShortcutPattern.Modifier | KQuickControls.ShortcutPattern.Key | KQuickControls.ShortcutPattern.ModifierAndKey
        onKeySequenceModified: {
            root.binding = keySequence
            root.bindingModified(root.binding)
        }
    }

    // ComboBox (visible when Button mode)
    Controls.ComboBox {
        id: buttonCombo
        visible: root.isMouseBinding
        model: [
            { text: i18nc("@item:inlistbox", "Middle Button"), value: "MouseMiddle" },
            { text: i18nc("@item:inlistbox", "Right Button"), value: "MouseRight" },
            { text: i18nc("@item:inlistbox", "Left Button"), value: "MouseLeft" },
            { text: i18nc("@item:inlistbox", "Back Button"), value: "MouseBack" },
            { text: i18nc("@item:inlistbox", "Forward Button"), value: "MouseForward" }
        ]
        textRole: "text"
        valueRole: "value"

        currentIndex: {
            for (let i = 0; i < model.length; i++) {
                if (model[i].value === root.binding) return i
            }
            return 0
        }

        onActivated: {
            root.binding = currentValue
            root.bindingModified(root.binding)
        }
    }
}
