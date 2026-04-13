/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    spacing: Kirigami.Units.smallSpacing
    visible: repeater.count > 0

    Component.onCompleted: kcm.refreshLeasableOutputs()

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: i18nc("@title:group", "Display Leasing")
            font.bold: true
        }

        Kirigami.ContextualHelpButton {
            toolTipText: xi18nc("@info:tooltip", "Allow leasing desktop outputs to VR/AR runtimes via DRM lease protocol.<nl/><nl/>Leasable outputs will be offered to compositors such as Monado for direct display access.<nl/><nl/>This can be used to lease AR glasses so that an OpenXR runtime can drive them directly.")
        }
    }

    Controls.Button {
        id: leaseButton
        Layout.alignment: Qt.AlignHCenter
        text: i18nc("@action:button", "Lease Selected")
        icon.name: leaseButton.waiting ? "" : "view-refresh"
        enabled: {
            if (leaseButton.waiting)
                return false
            for (var i = 0; i < kcm.leasableOutputs.length; i++) {
                if (kcm.leasableOutputs[i].leasable && !kcm.leasableOutputs[i].leased)
                    return true
            }
            return false
        }
        property bool waiting: false
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Controls.BusyIndicator {
                visible: leaseButton.waiting
                running: leaseButton.waiting
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            Kirigami.Icon {
                visible: !leaseButton.waiting
                source: "view-refresh"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            Controls.Label {
                text: leaseButton.waiting ? i18nc("@action:button", "Leasing…") : i18nc("@action:button", "Lease Selected")
            }
        }
        onClicked: {
            leaseButton.waiting = true
            kcm.refreshLeases()
        }
        Connections {
            target: kcm
            function onLeasableOutputsChanged() {
                if (leaseButton.waiting) {
                    leaseButton.waiting = false
                }
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 0

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: repeater
                model: kcm.leasableOutputs

                Controls.CheckBox {
                    Layout.alignment: Qt.AlignRight
                    checked: modelData.leasable
                    enabled: !modelData.leased
                    onToggled: kcm.setOutputLeasable(modelData.name, checked)
                }
            }
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: kcm.leasableOutputs

                Controls.Label {
                    Layout.alignment: Qt.AlignLeft
                    opacity: modelData.leased ? 0.6 : 1.0
                    text: {
                        var parts = [];
                        if (modelData.manufacturer) {
                            parts.push(modelData.manufacturer);
                        }
                        if (modelData.model) {
                            parts.push(modelData.model);
                        }
                        var label = parts.join(" ");
                        if (label) {
                            label = label + " (" + modelData.name + ")";
                        } else {
                            label = modelData.name;
                        }
                        if (modelData.leased) {
                            label += " — " + i18nc("@info:status", "leased");
                        }
                        return label;
                    }
                }
            }
        }
    }
}
