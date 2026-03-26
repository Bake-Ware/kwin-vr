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
        settingName: "depthBiasMultiplier"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "depthPrePassEnabled"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "depthTestEnabled"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "resetViewDelay"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "overlayPlacement"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "threadedRendering"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "multiview"
    }

    ColumnLayout {
        id: innerLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Kirigami.Units.largeSpacing

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "Advanced")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }

        // Overlay Placement
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:spinbox", "Overlay Placement:")
            }

            Controls.SpinBox {
                id: tOverlayPlacement
                from: 0
                to: 50
                value: kcm.settings.overlayPlacement
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Applications with higher <interface>Overlay Placement</interface> value will be rendered on top of other VR applications. Practically this allows to display KWin's windows over other running VR applications.")
            }
        }

        // Transparency section
        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title:group", "Transparency")
            font.bold: true
        }

        // Depth Bias Multiplier
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:spinbox", "Depth Bias Multiplier:")
            }

            Controls.SpinBox {
                id: tDepthBiasMultiplier
                from: 1
                to: 10000
                value: kcm.settings.depthBiasMultiplier * 10
                editable: true
                property real realValue: value / 10.0
                textFromValue: (value, locale) => (value / 10.0).toFixed(1)
                valueFromText: (text, locale) => Math.round(parseFloat(text) * 10)
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Controls how strongly depth bias affects transparency sorting. Higher values give stronger separation between overlapping transparent windows. Default: 10.0")
            }
        }

        // Depth Pre-Pass
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tDepthPrePassEnabled
                text: i18nc("@option:check", "Depth Pre-Pass")
                checked: kcm.settings.depthPrePassEnabled
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Enables a depth pre-pass before the main render pass. Can improve rendering performance in some cases by allowing early depth rejection.")
            }
        }

        // Depth Test
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tDepthTestEnabled
                text: i18nc("@option:check", "Depth Test")
                checked: kcm.settings.depthTestEnabled
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Enables depth testing for the scene. When disabled, objects are rendered in submission order without depth comparison.")
            }
        }

        // Rendering section
        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title:group", "Rendering")
            font.bold: true
        }

        // Async Rendering
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tThreadedRendering
                text: i18nc("@option:check", "Threaded Rendering")
                checked: kcm.settings.threadedRendering
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Renders the scene on a separate thread. May improve performance by decoupling rendering from the main thread, but can cause issues on some drivers. Requires VR Mode restart.")
            }
        }

        // Multiview
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tMultiview
                text: i18nc("@option:check", "Multiview")
                checked: kcm.settings.multiview
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Enables multiview rendering, which renders both eye views in a single pass. May improve performance on supported hardware. Requires VR Mode restart.")
            }
        }

        // Startup section
        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title:group", "Startup")
            font.bold: true
        }

        // Reset View Delay
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tResetViewEnabled
                text: i18nc("@option:check", "Recenter View on Startup after:")
                checked: kcm.settings.resetViewDelay >= 0
            }

            Controls.SpinBox {
                id: tResetViewDelay
                enabled: tResetViewEnabled.checked
                from: 0
                to: 300 // 0.0 to 30.0 s
                value: kcm.settings.resetViewDelay >= 0 ? Math.round(kcm.settings.resetViewDelay * 10) : 20
                editable: true
                property real realValue: value / 10.0
                textFromValue: (value, locale) => (value / 10.0).toFixed(1) + i18nc("@item:valuesuffix", " s")
                valueFromText: (text, locale) => Math.round(parseFloat(text) * 10)
            }
        }
    }

    Binding {
        target: kcm.settings
        property: "depthBiasMultiplier"
        value: tDepthBiasMultiplier.realValue
    }

    Binding {
        target: kcm.settings
        property: "depthPrePassEnabled"
        value: tDepthPrePassEnabled.checked
    }

    Binding {
        target: kcm.settings
        property: "depthTestEnabled"
        value: tDepthTestEnabled.checked
    }

    Binding {
        target: kcm.settings
        property: "resetViewDelay"
        value: tResetViewEnabled.checked ? tResetViewDelay.realValue : -1.0
    }

    Binding {
        target: kcm.settings
        property: "overlayPlacement"
        value: tOverlayPlacement.value
    }

    Binding {
        target: kcm.settings
        property: "threadedRendering"
        value: tThreadedRendering.checked
    }

    Binding {
        target: kcm.settings
        property: "multiview"
        value: tMultiview.checked
    }
}
