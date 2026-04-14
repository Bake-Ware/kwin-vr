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

    spacing: Kirigami.Units.largeSpacing

    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title", "Virtual Display Setup")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
    }

    Controls.CheckBox {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@option:check", "Hide virtual display frame in VR")
        checked: kcm.settings.hideVirtualDisplay
        onToggled: kcm.settings.hideVirtualDisplay = checked
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "width"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "height"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "scale"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "refreshrate"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "ppu"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "distance"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hideVirtualDisplay"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudEnabled"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudDistanceFraction"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudVerticalAngle"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudScaleH"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudScaleV"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudCurvature"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudShowNotifications"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudShowOsd"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudShowDock"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudShowAppletPopup"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "debugDisplayEnabled"
    }
    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "debugDisplayCorner"
    }

    // Main display configuration area
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 320

        // Width controls - TOP
        ColumnLayout {
            id: widthControls
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@title:group", "Width")
                font.bold: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing

                // Logical Width
                ColumnLayout {
                    spacing: 2
                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18nc("@label:spinbox", "Logical")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                    RowLayout {
                        Controls.SpinBox {
                            id: tWidth
                            value: kcm.settings.width
                            from: 100
                            to: 9999
                            editable: true
                        }
                        Controls.Label { text: i18nc("@item:valuesuffix", "px") }
                    }
                }

                // Physical Width (derived, cm)
                ColumnLayout {
                    spacing: 2
                    Controls.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18nc("@label:spinbox", "Physical")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                    RowLayout {
                        Controls.SpinBox {
                            id: physWidthCmBox
                            property bool updating: false
                            value: updating ? value : Math.round(tWidth.value / tPpu.value * 10)
                            from: 1
                            to: 100000
                            editable: true
                            textFromValue: (v, l) => (v / 10).toFixed(1)
                            valueFromText: (t, l) => Math.round(parseFloat(t) * 10)
                            onValueModified: {
                                updating = true
                                let widthCm = value / 10
                                tWidth.value = Math.max(100, Math.round(widthCm * tPpu.value))
                                updating = false
                            }
                        }
                        Controls.Label { text: i18nc("@item:valuesuffix", "cm") }
                    }
                }
            }
        }

        // Height controls - LEFT
        ColumnLayout {
            id: heightControls
            anchors.right: monitorFrame.left
            anchors.rightMargin: Kirigami.Units.largeSpacing
            anchors.verticalCenter: monitorFrame.verticalCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@title:group", "Height")
                font.bold: true
            }

            // Logical Height
            RowLayout {
                Controls.Label {
                    text: i18nc("@label:spinbox", "Logical")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    Layout.preferredWidth: 50
                }
                Controls.SpinBox {
                    id: tHeight
                    value: kcm.settings.height
                    from: 100
                    to: 9999
                    editable: true
                }
                Controls.Label { text: i18nc("@item:valuesuffix", "px") }
            }

            // Physical Height (derived, cm)
            RowLayout {
                Controls.Label {
                    text: i18nc("@label:spinbox", "Physical")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    Layout.preferredWidth: 50
                }
                Controls.SpinBox {
                    id: physHeightCmBox
                    property bool updating: false
                    value: updating ? value : Math.round(tHeight.value / tPpu.value * 10)
                    from: 1
                    to: 100000
                    editable: true
                    textFromValue: (v, l) => (v / 10).toFixed(1)
                    valueFromText: (t, l) => Math.round(parseFloat(t) * 10)
                    onValueModified: {
                        updating = true
                        let heightCm = value / 10
                        tHeight.value = Math.max(100, Math.round(heightCm * tPpu.value))
                        updating = false
                    }
                }
                Controls.Label { text: i18nc("@item:valuesuffix", "cm") }
            }
        }

        // Monitor Frame - CENTER
        MonitorFrame {
            id: monitorFrame

            readonly property real maxWidth: parent.width * 0.35
            readonly property real maxHeight: parent.height * 0.55

            width: Math.min(maxWidth, maxHeight * aspectRatio)
            height: width / aspectRatio

            anchors.centerIn: parent

            logicalWidth: tWidth.value
            logicalHeight: tHeight.value
            scale: tScale.value
            ppu: tPpu.value
        }
    }

    // Bottom settings row
    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing * 2

        // Scale
        ColumnLayout {
            spacing: 2
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@label:spinbox", "Scale")
                font.bold: true
            }
            Controls.SpinBox {
                id: tScale
                value: kcm.settings.scale
                from: 1
                to: 20
                editable: true
            }
        }

        // Refresh Rate
        ColumnLayout {
            spacing: 2
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@label:spinbox", "Refresh Rate")
                font.bold: true
            }
            RowLayout {
                Controls.SpinBox {
                    id: tRefreshRate
                    value: kcm.settings.refreshrate
                    from: 1
                    to: 500
                    editable: true
                }
                Controls.Label { text: i18nc("@item:valuesuffix", "Hz") }
            }
        }

        // PPU
        ColumnLayout {
            spacing: 2
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@label:spinbox", "Pixels/cm")
                font.bold: true
            }
            Controls.SpinBox {
                id: tPpu
                value: kcm.settings.ppu
                from: 1
                to: 100
                editable: true
            }
        }

        // Distance
        ColumnLayout {
            spacing: 2
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@label:spinbox", "Distance")
                font.bold: true
            }
            RowLayout {
                Controls.SpinBox {
                    id: tDistance
                    value: kcm.settings.distance
                    from: 50
                    to: 500
                    editable: true
                }
                Controls.Label { text: i18nc("@item:valuesuffix", "cm") }
            }
        }
    }

    Binding {
        target: kcm.settings
        property: "width"
        value: tWidth.value
    }
    Binding {
        target: kcm.settings
        property: "height"
        value: tHeight.value
    }
    Binding {
        target: kcm.settings
        property: "refreshrate"
        value: tRefreshRate.value
    }
    Binding {
        target: kcm.settings
        property: "scale"
        value: tScale.value
    }
    Binding {
        target: kcm.settings
        property: "ppu"
        value: tPpu.value
    }
    Binding {
        target: kcm.settings
        property: "distance"
        value: tDistance.value
    }

    // ── HUD Surface ──────────────────────────────────────────────────────

    // Auto-save HUD changes for live preview in VR
    Timer {
        id: hudSaveTimer
        interval: 300
        onTriggered: kcm.save()
    }
    function hudChanged() { hudSaveTimer.restart() }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    Controls.CheckBox {
        id: hudEnabledBox
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@option:check", "Show HUD calibration plane")
        checked: kcm.settings.hudEnabled
        onToggled: { kcm.settings.hudEnabled = checked; hudChanged() }
    }

    // HUD overlay window toggles
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing * 2

        Controls.CheckBox {
            text: i18nc("@option:check", "Notifications")
            checked: kcm.settings.hudShowNotifications
            onToggled: { kcm.settings.hudShowNotifications = checked; hudChanged() }
        }
        Controls.CheckBox {
            text: i18nc("@option:check", "OSD (volume, etc.)")
            checked: kcm.settings.hudShowOsd
            onToggled: { kcm.settings.hudShowOsd = checked; hudChanged() }
        }
        Controls.CheckBox {
            text: i18nc("@option:check", "Dock / Panel")
            checked: kcm.settings.hudShowDock
            onToggled: { kcm.settings.hudShowDock = checked; hudChanged() }
        }
        Controls.CheckBox {
            text: i18nc("@option:check", "Start Menu / Applets")
            checked: kcm.settings.hudShowAppletPopup
            onToggled: { kcm.settings.hudShowAppletPopup = checked; hudChanged() }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        enabled: hudEnabledBox.checked
        opacity: enabled ? 1.0 : 0.5
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "HUD Surface")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        }

        // Distance
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing * 4
            Layout.rightMargin: Kirigami.Units.largeSpacing * 4
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Distance")
                Layout.preferredWidth: 90
            }
            Controls.Slider {
                id: hudDistSlider
                Layout.fillWidth: true
                from: 10; to: 100; stepSize: 1
                value: kcm.settings.hudDistanceFraction
                onMoved: { kcm.settings.hudDistanceFraction = value; hudChanged() }
            }
            Controls.SpinBox {
                from: 10; to: 100; editable: true
                value: hudDistSlider.value
                onValueModified: { hudDistSlider.value = value; kcm.settings.hudDistanceFraction = value; hudChanged() }
            }
            Controls.Label { text: "%"; Layout.preferredWidth: 20 }
        }

        // Vertical Angle
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing * 4
            Layout.rightMargin: Kirigami.Units.largeSpacing * 4
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Vertical Angle")
                Layout.preferredWidth: 90
            }
            Controls.Slider {
                id: hudAngleSlider
                Layout.fillWidth: true
                from: -45; to: 45; stepSize: 1
                value: kcm.settings.hudVerticalAngle
                onMoved: { kcm.settings.hudVerticalAngle = value; hudChanged() }
            }
            Controls.SpinBox {
                from: -45; to: 45; editable: true
                value: hudAngleSlider.value
                onValueModified: { hudAngleSlider.value = value; kcm.settings.hudVerticalAngle = value; hudChanged() }
            }
            Controls.Label { text: "\u00b0"; Layout.preferredWidth: 20 }
        }

        // Horizontal Scale
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing * 4
            Layout.rightMargin: Kirigami.Units.largeSpacing * 4
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Scale H")
                Layout.preferredWidth: 90
            }
            Controls.Slider {
                id: hudScaleHSlider
                Layout.fillWidth: true
                from: 0.1; to: 3.0; stepSize: 0.05
                value: kcm.settings.hudScaleH
                onMoved: { kcm.settings.hudScaleH = value; hudChanged() }
            }
            Controls.SpinBox {
                from: 10; to: 300; editable: true
                value: Math.round(hudScaleHSlider.value * 100)
                textFromValue: (v, l) => (v / 100).toFixed(2)
                valueFromText: (t, l) => Math.round(parseFloat(t) * 100)
                onValueModified: { const v = value / 100; hudScaleHSlider.value = v; kcm.settings.hudScaleH = v; hudChanged() }
            }
            Controls.Label { text: "x"; Layout.preferredWidth: 20 }
        }

        // Vertical Scale
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing * 4
            Layout.rightMargin: Kirigami.Units.largeSpacing * 4
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Scale V")
                Layout.preferredWidth: 90
            }
            Controls.Slider {
                id: hudScaleVSlider
                Layout.fillWidth: true
                from: 0.1; to: 3.0; stepSize: 0.05
                value: kcm.settings.hudScaleV
                onMoved: { kcm.settings.hudScaleV = value; hudChanged() }
            }
            Controls.SpinBox {
                from: 10; to: 300; editable: true
                value: Math.round(hudScaleVSlider.value * 100)
                textFromValue: (v, l) => (v / 100).toFixed(2)
                valueFromText: (t, l) => Math.round(parseFloat(t) * 100)
                onValueModified: { const v = value / 100; hudScaleVSlider.value = v; kcm.settings.hudScaleV = v; hudChanged() }
            }
            Controls.Label { text: "x"; Layout.preferredWidth: 20 }
        }

        // Curvature
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing * 4
            Layout.rightMargin: Kirigami.Units.largeSpacing * 4
            spacing: Kirigami.Units.largeSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Curvature")
                Layout.preferredWidth: 90
            }
            Controls.Slider {
                id: hudCurvSlider
                Layout.fillWidth: true
                from: 0.0; to: 6.0; stepSize: 0.1
                value: kcm.settings.hudCurvature
                onMoved: { kcm.settings.hudCurvature = value; hudChanged() }
            }
            Controls.SpinBox {
                from: 0; to: 60; editable: true
                value: Math.round(hudCurvSlider.value * 10)
                textFromValue: (v, l) => (v / 10).toFixed(1)
                valueFromText: (t, l) => Math.round(parseFloat(t) * 10)
                onValueModified: { const v = value / 10; hudCurvSlider.value = v; kcm.settings.hudCurvature = v; hudChanged() }
            }
            Controls.Label { text: "rad"; Layout.preferredWidth: 20 }
        }
    }

    // ── Debug Display ────────────────────────────────────────────────────
    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing * 2

        Controls.CheckBox {
            id: debugEnabledBox
            text: i18nc("@option:check", "Show debug display")
            checked: kcm.settings.debugDisplayEnabled
            onToggled: { kcm.settings.debugDisplayEnabled = checked; hudChanged() }
        }

        RowLayout {
            enabled: debugEnabledBox.checked
            opacity: enabled ? 1.0 : 0.5
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:listbox", "Corner:")
            }
            Controls.ComboBox {
                model: [
                    i18nc("@item:inlistbox", "Top Left"),
                    i18nc("@item:inlistbox", "Top Right"),
                    i18nc("@item:inlistbox", "Bottom Left"),
                    i18nc("@item:inlistbox", "Bottom Right")
                ]
                currentIndex: kcm.settings.debugDisplayCorner
                onActivated: (index) => { kcm.settings.debugDisplayCorner = index; hudChanged() }
            }
        }
    }
}
