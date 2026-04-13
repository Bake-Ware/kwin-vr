/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    required property Xray xray
    required property VrPicking picking

    // Ray length calculation
    readonly property real rayLength: {
        if (root.xray.grabbedObject) {
            return root.xray.grabbedObjectPose.position.length()
        }
        if (root.picking.lastPick.hitType !== PickResult.Null) {
            return root.picking.lastPick.distance
        }
        return root.xray.defaultLength
    }

    // Ray visibility
    readonly property bool rayVisible: root.xray.enabled && root.xray.currentColor.a > 0

    readonly property Binding vrRayLengthBinding: Binding {
        target: root.xray.vrRay
        property: "length"
        value: root.rayLength
        when: root.xray.vrRay
    }
    readonly property Binding vrRayColorBinding: Binding {
        target: root.xray.vrRay
        property: "baseColor"
        value: root.xray.currentColor
        when: root.xray.vrRay
    }
    readonly property Binding vrRayVisibleBinding: Binding {
        target: root.xray.vrRay
        property: "visible"
        value: root.rayVisible
        when: root.xray.vrRay
    }
}
