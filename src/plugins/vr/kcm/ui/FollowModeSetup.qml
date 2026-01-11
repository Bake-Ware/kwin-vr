/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

Item {
    id: root

    implicitHeight: innerLayout.implicitHeight

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followEnabled"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followFovH"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followFovV"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followStopFovH"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followStopFovV"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followDelay"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followSpeed"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "followWorldUpAlignment"
    }

    // Centered content wrapper
    ColumnLayout {
        id: innerLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Kirigami.Units.largeSpacing

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "Follow Mode Setup")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }

        // Enable checkbox at top
        Controls.CheckBox {
            id: tFollowEnabled
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@option:check", "Enable Follow Mode by Default")
            checked: kcm.settings.followEnabled
            font.bold: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Controls.CheckBox {
                id: tFollowWorldUpAlignment
                text: i18nc("@option:check", "Align to World Up (Horizon)")
                checked: kcm.settings.followWorldUpAlignment
                font.bold: true
            }
            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "When enabled, windows will stay level with the horizon.<nl/>When disabled, windows will follow your head's tilt (useful when lying down).")
            }
        }

        // FOV settings
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Controls.Label {
                    text: i18nc("@label", "Start FOV")
                    font.bold: true
                }
                Kirigami.ContextualHelpButton {
                    toolTipText: xi18nc("@info:tooltip", "When all windows are outside this zone, rotation begins after a delay.")
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Controls.Label { text: i18nc("@label:spinbox", "H") }
                    Controls.SpinBox {
                        id: tFollowFovH
                        value: kcm.settings.followFovH
                        from: 5
                        to: 90
                        editable: true
                    }
                    Controls.Label { text: i18nc("@item:valuesuffix", "°") }
                }

                RowLayout {
                    Controls.Label { text: i18nc("@label:spinbox", "V") }
                    Controls.SpinBox {
                        id: tFollowFovV
                        value: kcm.settings.followFovV
                        from: 5
                        to: 90
                        editable: true
                    }
                    Controls.Label { text: i18nc("@item:valuesuffix", "°") }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Controls.Label {
                    text: i18nc("@label", "Stop FOV")
                    font.bold: true
                }
                Kirigami.ContextualHelpButton {
                    toolTipText: xi18nc("@info:tooltip", "Rotation stops when the closest window reaches this center zone.")
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Controls.Label { text: i18nc("@label:spinbox", "H") }
                    Controls.SpinBox {
                        id: tFollowStopFovH
                        value: kcm.settings.followStopFovH
                        from: 1
                        to: tFollowFovH.value
                        editable: true
                    }
                    Controls.Label { text: i18nc("@item:valuesuffix", "°") }
                }

                RowLayout {
                    Controls.Label { text: i18nc("@label:spinbox", "V") }
                    Controls.SpinBox {
                        id: tFollowStopFovV
                        value: kcm.settings.followStopFovV
                        from: 1
                        to: tFollowFovV.value
                        editable: true
                    }
                    Controls.Label { text: i18nc("@item:valuesuffix", "°") }
                }
            }
        }

        // Bottom settings row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing * 2

            // Delay
            ColumnLayout {
                spacing: 2
                Controls.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18nc("@label:spinbox", "Delay")
                    font.bold: true
                }
                RowLayout {
                    Controls.SpinBox {
                        id: tFollowDelay
                        value: kcm.settings.followDelay * 100
                        from: 0
                        to: 500
                        editable: true
                        property real realValue: value / 100.0
                        textFromValue: (value, locale) => (value / 100.0).toFixed(2)
                        valueFromText: (text, locale) => Math.round(parseFloat(text) * 100)
                    }
                    Controls.Label { text: i18nc("@item:valuesuffix", "s") }
                }
            }

            // Speed
            ColumnLayout {
                spacing: 2
                Controls.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18nc("@label:spinbox", "Speed")
                    font.bold: true
                }
                Controls.SpinBox {
                    id: tFollowSpeed
                    value: kcm.settings.followSpeed * 100
                    from: 10
                    to: 1000
                    editable: true
                    property real realValue: value / 100.0
                    textFromValue: (value, locale) => (value / 100.0).toFixed(2)
                    valueFromText: (text, locale) => Math.round(parseFloat(text) * 100)
                }
            }
        }
    }

    Binding {
        target: kcm.settings
        property: "followEnabled"
        value: tFollowEnabled.checked
    }
    Binding {
        target: kcm.settings
        property: "followFovH"
        value: tFollowFovH.value
    }
    Binding {
        target: kcm.settings
        property: "followFovV"
        value: tFollowFovV.value
    }
    Binding {
        target: kcm.settings
        property: "followStopFovH"
        value: tFollowStopFovH.value
    }
    Binding {
        target: kcm.settings
        property: "followStopFovV"
        value: tFollowStopFovV.value
    }
    Binding {
        target: kcm.settings
        property: "followDelay"
        value: tFollowDelay.realValue
    }
    Binding {
        target: kcm.settings
        property: "followSpeed"
        value: tFollowSpeed.realValue
    }
    Binding {
        target: kcm.settings
        property: "followWorldUpAlignment"
        value: tFollowWorldUpAlignment.checked
    }
}
