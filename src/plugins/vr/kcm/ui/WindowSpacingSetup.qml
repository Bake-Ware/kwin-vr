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

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "zWindowMarginTop"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "zWindowMarginBottom"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "zSurfaceMarginTop"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "zSurfaceMarginBottom"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "minTransientNormalSpacing"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "defaultWindowCurvature"
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    Controls.Label {
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@title:group", "Window Spacing")
        font.bold: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: i18nc("@label:spinbox", "Window Margin Top (cm):")
        }

        Controls.SpinBox {
            id: tZMarginTop
            from: 1
            to: 500
            value: kcm.settings.zWindowMarginTop * 100
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Controls.Label {
            text: i18nc("@label:spinbox", "Bottom (cm):")
        }

        Controls.SpinBox {
            id: tZMarginBottom
            from: 0
            to: 500
            value: kcm.settings.zWindowMarginBottom * 100
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Minimum Z depth (top and bottom) for windows in the 3D scene. Also used as margins for single-surface windows (Thumbnail modes).")
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: i18nc("@label:spinbox", "Surface Margin Top (cm):")
        }

        Controls.SpinBox {
            id: tZSurfaceMarginTop
            from: 1
            to: 500
            value: kcm.settings.zSurfaceMarginTop * 100
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Controls.Label {
            text: i18nc("@label:spinbox", "Bottom (cm):")
        }

        Controls.SpinBox {
            id: tZSurfaceMarginBottom
            from: 0
            to: 500
            value: kcm.settings.zSurfaceMarginBottom * 100
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Z margins (top and bottom) for individual surfaces within a window (Qt Native 3D mode). The total surface stack depth is clamped to at least the window margins above.")
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: i18nc("@label:spinbox", "Min Transient Normal Spacing (cm):")
        }

        Controls.SpinBox {
            id: tMinTransientNormalSpacing
            from: 0
            to: 1000
            value: kcm.settings.minTransientNormalSpacing * 100
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Minimum Z space between transient normal windows (e.g. settings dialogs) and their parent window.")
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: i18nc("@label:spinbox", "Default Window Curvature (arc radians):")
        }

        Controls.SpinBox {
            id: tDefaultCurvature
            from: 0
            to: 600
            value: Math.round(kcm.settings.defaultWindowCurvature * 100)
            stepSize: 10
            property real realValue: value / 100
            textFromValue: function(value, locale) {
                return (value / 100).toFixed(2)
            }
            valueFromText: function(text, locale) {
                return Math.round(parseFloat(text) * 100)
            }
        }

        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Curvature of VR windows in arc radians. 0 = flat, larger values wrap the surface tighter around the viewer. Typical: 0.5–2.0.")
        }
    }

    Binding {
        target: kcm.settings
        property: "zWindowMarginTop"
        value: tZMarginTop.realValue
    }

    Binding {
        target: kcm.settings
        property: "zWindowMarginBottom"
        value: tZMarginBottom.realValue
    }

    Binding {
        target: kcm.settings
        property: "zSurfaceMarginTop"
        value: tZSurfaceMarginTop.realValue
    }

    Binding {
        target: kcm.settings
        property: "zSurfaceMarginBottom"
        value: tZSurfaceMarginBottom.realValue
    }

    Binding {
        target: kcm.settings
        property: "minTransientNormalSpacing"
        value: tMinTransientNormalSpacing.realValue
    }

    Binding {
        target: kcm.settings
        property: "defaultWindowCurvature"
        value: tDefaultCurvature.realValue
    }
}
