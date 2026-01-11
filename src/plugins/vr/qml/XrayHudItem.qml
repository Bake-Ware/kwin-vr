/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D

Rectangle {
    id: root

    required property pickResult pickResult
    property real contentScale: 3
    property real padding: 8 * contentScale
    property int textSize: 12 * contentScale

    color: "transparent"
    radius: 6 * contentScale
    border.color: "#66ffffff"
    border.width: contentScale

    implicitWidth: layout.implicitWidth + padding * 2
    implicitHeight: layout.implicitHeight + padding * 2

    component KeyLabel: Label {
        color: "#88ccff"
        font.family: "monospace"
        font.pointSize: root.textSize
    }

    component ValueLabel: Label {
        color: "#ffffff"
        font.family: "monospace"
        font.pointSize: root.textSize
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        columns: 2
        columnSpacing: 9 * root.contentScale
        rowSpacing: 3 * root.contentScale

        KeyLabel {
            text: {
                const pick = root.pickResult
                if (pick.itemHit)
                    return "Item:"
                if (pick.objectHit)
                    return "Model:"
                return "Hit:"
            }
        }
        ValueLabel {
            text: {
                const pick = root.pickResult
                const obj = pick.itemHit || pick.objectHit
                if (!obj)
                    return "N/A"
                if (obj.objectName)
                    return obj.objectName
                // Extract type name from toString(), e.g. "KwinApplicationWindow_QMLTYPE_42(0x...)" -> "KwinApplicationWindow"
                const str = obj.toString()
                const match = str.match(/^(\w+)/)
                return match ? match[1] : str
            }
        }

        KeyLabel { text: "UV Pos:" }
        ValueLabel { text: formatVector2(root.pickResult.uvPosition) }

        KeyLabel { text: "Scene Pos:" }
        ValueLabel { text: formatVector3(root.pickResult.scenePosition) }

        KeyLabel { text: "Local Pos:" }
        ValueLabel { text: formatVector3(root.pickResult.position) }

        KeyLabel { text: "Distance:" }
        ValueLabel { text: root.pickResult.distance.toFixed(2) }
    }

    function formatVector2(v: point): string {
        if (!v)
            return "N/A"
        return "(" + v.x.toFixed(2) + ", " + v.y.toFixed(2) + ")"
    }

    function formatVector3(v: vector3d): string {
        if (!v)
            return "N/A"
        return "(" + v.x.toFixed(2) + ", " + v.y.toFixed(2) + ", " + v.z.toFixed(2) + ")"
    }
}
