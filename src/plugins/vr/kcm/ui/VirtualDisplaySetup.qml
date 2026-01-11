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
}
