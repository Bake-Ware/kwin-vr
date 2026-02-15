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
        settingName: "xrTestEnabled"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "overlayPlacement"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "blend"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "windowMode"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "defaultCurvature"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "vignetteEnabled"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "vignetteFadeWidth"
    }

    // Centered content wrapper
    ColumnLayout {
        id: innerLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Kirigami.Units.largeSpacing

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "General")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }

        // Launch VR button
        Controls.Button {
            Layout.alignment: Qt.AlignHCenter
            text: kcm.vrActive ? i18nc("@action:button", "Stop VR Mode") : i18nc("@action:button", "Activate VR Mode")
            icon.name: kcm.vrActive ? "media-playback-stop" : "video-display"
            onClicked: kcm.vrActive = !kcm.vrActive
        }

        // OpenXR Test settings
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tXrTestEnabled
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@option:check", "Run OpenXR Test on Startup")
                checked: kcm.settings.xrTestEnabled
            }

            Controls.Button {
                Layout.alignment: Qt.AlignHCenter
                text: kcm.xrTest ? i18nc("@action:button", "Stop OpenXR Test") : i18nc("@action:button", "Run OpenXR Test")
                icon.name: kcm.xrTest ? "media-playback-stop" : "system-run"
                onClicked: kcm.xrTest = !kcm.xrTest
            }
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

        // Transparent Background (Blend)
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tBlend
                Layout.alignment: Qt.AlignHCenter
                text: i18nc("@option:check", "Transparent Background")
                checked: kcm.settings.blend
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Allows to overlay KWin's windows on passthrough video from cameras (if supported by headset).")
            }
        }

        // Window Rendering Mode
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:listbox", "Window Mode:")
            }

            Controls.ComboBox {
                id: tWindowMode
                model: [i18nc("@item:inlistbox", "Qt Native 3D"), i18nc("@item:inlistbox", "KWin Thumbnail 3D"), i18nc("@item:inlistbox", "KWin Thumbnail 2D")]
                currentIndex: kcm.settings.windowMode
                onActivated: kcm.settings.windowMode = currentIndex
            }
            Kirigami.ContextualHelpButton {
                property string wqt3d: xi18nc("@info:tooltip", "<emphasis strong='true'>Qt Native 3D</emphasis> - Fastest mode, but not everything may work correctly. Every window is a set of 3D models: surfaces, decroations and a shadow.")
                property string wkw3d: xi18nc("@info:tooltip", "<emphasis strong='true'>KWin Thumbnail 3D</emphasis> - Slower mode, offscreen rendering is performed. Rendered windows are exactly the same as for 2D desktop. Every window is a single 3D model.")
                property string wkw2d: xi18nc("@info:tooltip", "<emphasis strong='true'>KWin Thumbnail 2D</emphasis> - The same as <emphasis strong='true'>KWin Thumbnail 3D</emphasis>, but windows are rendered as 2D components in the 3D scene. Used only for testing.")
                toolTipText: wqt3d + "<br><br>" + wkw3d + "<br><br>" + wkw2d
            }
        }

        // Default Curvature
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: i18nc("@label:slider", "Default Curvature:")
            }

            Controls.Slider {
                id: tDefaultCurvature
                from: 0.0
                to: 6.0
                stepSize: 0.1
                value: kcm.settings.defaultCurvature
                implicitWidth: 200
            }

            Controls.Label {
                text: tDefaultCurvature.value.toFixed(1)
                Layout.minimumWidth: 30
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Curvature applied to windows when they enter VR mode. 0 = flat, higher values = more curved.")
            }
        }

        // Edge Vignette
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: tVignetteEnabled
                text: i18nc("@option:check", "Edge Vignette")
                checked: kcm.settings.vignetteEnabled
                onToggled: kcm.settings.vignetteEnabled = checked
            }

            Controls.Slider {
                id: tVignetteFadeWidth
                enabled: tVignetteEnabled.checked
                from: 0.02
                to: 0.5
                stepSize: 0.01
                value: kcm.settings.vignetteFadeWidth
                onMoved: kcm.settings.vignetteFadeWidth = value
                implicitWidth: 150
            }

            Controls.Label {
                text: Math.round(tVignetteFadeWidth.value * 100) + "%"
                Layout.minimumWidth: 40
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Fades edges of the viewport to black to mask parallax clipping artifacts when objects are partially outside the field of view.")
            }
        }

        // Shortcuts info
        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18nc("@title:group", "Keyboard Shortcuts")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            textFormat: Text.RichText
            text: i18nc("@info", "VR shortcuts can be configured in <b>Settings → Keyboard → Shortcuts → System Services → VR Interface</b>.<br>" +
                  "Available shortcuts: Realign Window, Grab Window, Grab All Windows,<br>" +
                  "Toggle HUD, Toggle Ray, Reset View, Toggle PIP, Open Radial Menu")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Binding {
        target: kcm.settings
        property: "xrTestEnabled"
        value: tXrTestEnabled.checked
    }

    Binding {
        target: kcm.settings
        property: "overlayPlacement"
        value: tOverlayPlacement.value
    }

    Binding {
        target: kcm.settings
        property: "blend"
        value: tBlend.checked
    }

    Binding {
        target: kcm.settings
        property: "defaultCurvature"
        value: tDefaultCurvature.value
    }
}
