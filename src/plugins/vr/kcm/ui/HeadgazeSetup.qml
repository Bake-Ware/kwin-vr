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
    id: root
    spacing: Kirigami.Units.smallSpacing

    // Setting state bindings
    resources: [
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazePositionX"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazePositionY"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazePositionZ"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazeRotationHorizontal"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazeRotationVertical"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazeColor"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "headgazeGrabColor"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "pointerInhibitDelay"
        },
        KCMUtils.SettingStateBinding {
            configObject: kcm.settings
            settingName: "blockOtherPointerMotion"
        }
    ]

    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title", "Head Ray")
        font.bold: true
    }

    // 3D Preview
    HeadgazePreview3D {
        id: preview3D
        Layout.fillWidth: true
        Layout.preferredHeight: 280
        Layout.maximumHeight: 350

        rayColor: kcm.settings.headgazeColor

        // Display configuration bindings
        displayWidth: kcm.settings.width / Math.max(1, kcm.settings.ppu)
        displayHeight: kcm.settings.height / Math.max(1, kcm.settings.ppu)
        displayDistance: kcm.settings.distance

        // Use Synchronizer for robust two-way binding
        Synchronizer on positionX {
            sourceObject: kcm.settings
            sourceProperty: "headgazePositionX"
        }
        Synchronizer on positionY {
            sourceObject: kcm.settings
            sourceProperty: "headgazePositionY"
        }
        Synchronizer on positionZ {
            sourceObject: kcm.settings
            sourceProperty: "headgazePositionZ"
        }
        Synchronizer on rotationHorizontal {
            sourceObject: kcm.settings
            sourceProperty: "headgazeRotationHorizontal"
        }
        Synchronizer on rotationVertical {
            sourceObject: kcm.settings
            sourceProperty: "headgazeRotationVertical"
        }
    }

    // Unified Grid for alignment
    GridLayout {
        columns: 2
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        // Rotation Header
        Controls.Label {
            Layout.columnSpan: 2
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title:group", "Rotation (degrees)")
            font.italic: true
        }

        Controls.Label {
            text: i18nc("@label:slider", "Horizontal:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: -45; to: 45; stepSize: 1; decimals: 1
            inverted: true
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headgazeRotationHorizontal"
            }
        }

        Controls.Label {
            text: i18nc("@label:slider", "Vertical:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: -45; to: 45; stepSize: 1; decimals: 1
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headgazeRotationVertical"
            }
        }

        // Position Header
        Controls.Label {
            Layout.columnSpan: 2
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: i18nc("@title:group", "Position (cm)")
            font.italic: true
        }

        Controls.Label {
            text: i18nc("@label:slider", "X:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: -50; to: 50; stepSize: 1; decimals: 1
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headgazePositionX"
            }
        }

        Controls.Label {
            text: i18nc("@label:slider", "Y:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: -50; to: 50; stepSize: 1; decimals: 1
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headgazePositionY"
            }
        }

        Controls.Label {
            text: i18nc("@label:slider", "Z:")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
        ValueSlider {
            Layout.fillWidth: true
            label: ""
            labelWidth: 0
            from: -50; to: 50; stepSize: 1; decimals: 1
            Synchronizer on value {
                sourceObject: kcm.settings
                sourceProperty: "headgazePositionZ"
            }
        }
    }

    // Colors section
    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18nc("@title:group", "Colors")
        font.italic: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        // Idle color
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:chooser", "Idle:")
            }

            ColorPickerButton {
                dialogTitle: i18nc("@title:window", "Select Idle Color")
                Synchronizer on selectedColor {
                    sourceObject: kcm.settings
                    sourceProperty: "headgazeColor"
                }
            }
        }

        // Grab color
        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:chooser", "Grab:")
            }

            ColorPickerButton {
                dialogTitle: i18nc("@title:window", "Select Grab Color")
                Synchronizer on selectedColor {
                    sourceObject: kcm.settings
                    sourceProperty: "headgazeGrabColor"
                }
            }
        }
    }

    // Misc section
    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18nc("@title:group", "Misc")
        font.italic: true
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        // Pointer Move Inhibitor
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: pointerInhibitEnabled
                text: i18nc("@option:check", "Inhibit pointer movement after mouse button press for:")
                checked: kcm.settings.pointerInhibitDelay >= 0
                onToggled: {
                    if (checked) {
                        if (kcm.settings.pointerInhibitDelay < 0) {
                            kcm.settings.pointerInhibitDelay = 100
                        }
                    } else {
                        kcm.settings.pointerInhibitDelay = -1
                    }
                }
            }

            Controls.SpinBox {
                enabled: pointerInhibitEnabled.checked
                from: 0
                to: 1000
                value: kcm.settings.pointerInhibitDelay >= 0 ? Math.round(kcm.settings.pointerInhibitDelay) : 100
                editable: true
                textFromValue: (value, locale) => value + i18nc("@item:valuesuffix", " ms")
                valueFromText: (text, locale) => Math.round(parseFloat(text))
                onValueChanged: {
                    if (pointerInhibitEnabled.checked && value !== Math.max(1, kcm.settings.pointerInhibitDelay)) {
                        kcm.settings.pointerInhibitDelay = value
                    }
                }
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Due to head shaking, some applications might treat mouse button clicks as a press - move - release sequence. Pointer movement will be inhibited between press and release for the specified time.")
            }
        }

        // Pointer movement blocking
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                text: i18nc("@option:check", "Block pointer motion from other input sources")
                checked: kcm.settings.blockOtherPointerMotion
                onToggled: kcm.settings.blockOtherPointerMotion = checked
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "When the pointer is grabbed by an application, events will be processed as usual even if this option is enabled. Example: a game can grab the pointer and use relative mouse movement to move the camera.")
            }
        }

    }
}
