/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Qt.labs.synchronizer

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

Item {
    id: root

    implicitHeight: innerLayout.implicitHeight

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "shortcutResizeStep"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "shortcutCurvatureStep"
    }

    KCMUtils.SettingStateBinding {
        configObject: kcm.settings
        settingName: "hudPinScale"
    }

    ColumnLayout {
        id: innerLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Kirigami.Units.largeSpacing

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "Shortcut Actions")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            text: i18nc("@info", "These parameters tune the VR shortcut actions. The key bindings themselves can be changed in System Settings → Keyboard → Shortcuts (KWin section).")
            opacity: 0.7
        }

        Kirigami.FormLayout {
            Layout.alignment: Qt.AlignHCenter

            ValueSlider {
                Kirigami.FormData.label: i18nc("@option", "Window resize step")
                from: 0.02
                to: 0.5
                stepSize: 0.02
                decimals: 2
                Synchronizer on value {
                    sourceObject: kcm.settings
                    sourceProperty: "shortcutResizeStep"
                }
            }

            ValueSlider {
                Kirigami.FormData.label: i18nc("@option", "Curvature step")
                from: 0.05
                to: 1.0
                stepSize: 0.05
                decimals: 2
                Synchronizer on value {
                    sourceObject: kcm.settings
                    sourceProperty: "shortcutCurvatureStep"
                }
            }

            ValueSlider {
                Kirigami.FormData.label: i18nc("@option", "Pinned window scale")
                from: 0.1
                to: 1.0
                stepSize: 0.05
                decimals: 2
                Synchronizer on value {
                    sourceObject: kcm.settings
                    sourceProperty: "hudPinScale"
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Controls.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18nc("@title", "Default Bindings")
            font.bold: true
        }

        Kirigami.FormLayout {
            Layout.alignment: Qt.AlignHCenter

            Controls.Label {
                Kirigami.FormData.label: i18nc("@option", "Grow window:")
                text: "Ctrl+Meta+="
            }
            Controls.Label {
                Kirigami.FormData.label: i18nc("@option", "Shrink window:")
                text: "Ctrl+Meta+-"
            }
            Controls.Label {
                Kirigami.FormData.label: i18nc("@option", "Increase curvature:")
                text: "Ctrl+Meta+]"
            }
            Controls.Label {
                Kirigami.FormData.label: i18nc("@option", "Decrease curvature:")
                text: "Ctrl+Meta+["
            }
            Controls.Label {
                Kirigami.FormData.label: i18nc("@option", "Pin window to HUD:")
                text: "Ctrl+Meta+P"
            }
        }
    }
}
