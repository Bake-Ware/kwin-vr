/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property string label: ""
    property real value: 0.5
    property real from: 0.0
    property real to: 1.0
    property real stepSize: 0.05
    property int labelWidth: Kirigami.Units.gridUnit * 8
    property int decimals: 2
    property bool inverted: false

    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: root.label
        visible: root.label !== ""
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        Layout.preferredWidth: root.labelWidth > 0 ? root.labelWidth : implicitWidth
        horizontalAlignment: Text.AlignRight
    }

    Controls.Slider {
        id: slider
        from: root.from
        to: root.to
        stepSize: root.stepSize
        snapMode: Controls.Slider.SnapAlways
        Layout.fillWidth: true
        value: root.inverted ? -root.value : root.value
        onMoved: root.value = root.inverted ? -value : value
    }

    Controls.SpinBox {
        id: spinBox
        from: Math.min(root.from, root.to) * Math.pow(10, root.decimals)
        to: Math.max(root.from, root.to) * Math.pow(10, root.decimals)
        stepSize: Math.abs(root.stepSize) * Math.pow(10, root.decimals)
        value: root.value * Math.pow(10, root.decimals)
        onValueModified: root.value = value / Math.pow(10, root.decimals)
        editable: true
        Layout.alignment: Qt.AlignVCenter

        property real realValue: value / Math.pow(10, root.decimals)

        textFromValue: function(value, locale) {
            return Number(value / Math.pow(10, root.decimals)).toLocaleString(locale, 'f', root.decimals)
        }
        valueFromText: function(text, locale) {
            return Number.fromLocaleString(locale, text) * Math.pow(10, root.decimals)
        }
    }
}
