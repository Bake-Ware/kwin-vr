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
    property bool openXrRuntimeInitialized: false
    Component.onCompleted: kcm.refreshOpenXrRuntimeCandidates()

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "xrTestEnabled"
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
        settingName: "openXrRuntimeJson"
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
                toolTipText: wqt3d + "\n\n" + wkw3d + "\n\n" + wkw2d
            }
        }

        WindowSpacingSetup {
            Layout.fillWidth: true
        }

        // OpenXR Runtime section
        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title:group", "OpenXR Runtime")
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.ComboBox {
                id: tOpenXrRuntimeJson
                Layout.preferredWidth: Kirigami.Units.gridUnit * 20
                editable: true
                model: [" "].concat(kcm.openXrRuntimeCandidates)
                onActivated: editText = currentText.trim()
                Component.onCompleted: {
                    currentIndex = -1;
                    editText = kcm.settings.openXrRuntimeJson;
                    root.openXrRuntimeInitialized = true;
                }
                Connections {
                    target: kcm.settings
                    function onOpenXrRuntimeJsonChanged() {
                        tOpenXrRuntimeJson.editText = kcm.settings.openXrRuntimeJson;
                    }
                }
            }

            Kirigami.ContextualHelpButton {
                toolTipText: xi18nc("@info:tooltip", "Absolute path to runtime JSON for OpenXR loader initialization.<nl/><nl/>Leave empty to skip explicit loader initialization.")
            }
        }

        LeasableOutputSetup {
            Layout.fillWidth: true
        }
    }

    Binding {
        target: kcm.settings
        property: "xrTestEnabled"
        value: tXrTestEnabled.checked
    }

    Binding {
        target: kcm.settings
        property: "blend"
        value: tBlend.checked
    }

    Binding {
        target: kcm.settings
        property: "openXrRuntimeJson"
        value: tOpenXrRuntimeJson.editText.trim()
        when: root.openXrRuntimeInitialized
    }

}
