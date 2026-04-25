/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * SelectionPrism — wireframe rect drawn between two anchor points in
 * scene space. Used for the right-click drag selection gesture that
 * spawns a Free-mode CurvedPlane container.
 *
 * Owners (XrScene) drive `active`, `anchor1`, `anchor2`. SelectionPrism
 * draws only — it does not capture or commit. Capture logic lives in
 * XrScene's gesture handler.
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    property bool active: false
    property vector3d anchor1: Qt.vector3d(0, 0, 0)
    property vector3d anchor2: Qt.vector3d(0, 0, 0)

    visible: active

    readonly property vector3d centre: Qt.vector3d(
        (anchor1.x + anchor2.x) / 2,
        (anchor1.y + anchor2.y) / 2,
        (anchor1.z + anchor2.z) / 2)

    readonly property real spanX: Math.abs(anchor2.x - anchor1.x)
    readonly property real spanY: Math.abs(anchor2.y - anchor1.y)
    readonly property real spanZ: Math.max(0.02, Math.abs(anchor2.z - anchor1.z))

    Model {
        id: box
        position: root.centre
        source: "#Cube"
        scale: Qt.vector3d(Math.max(root.spanX, 0.02) / 100,
                           Math.max(root.spanY, 0.02) / 100,
                           root.spanZ / 100)
        depthBias: -100
        materials: DefaultMaterial {
            diffuseColor: Qt.rgba(0.4, 0.8, 1.0, 1.0)
            opacity: 0.15
            lighting: DefaultMaterial.NoLighting
            cullMode: Material.NoCulling
            depthDrawMode: Material.OpaqueOnlyDepthDraw
        }
    }
}
