/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick3D
import QtQuick3D.Xr
import QtQuick3D.Helpers
import QtQuick

Model {
    id: root
    property color baseColor: "#cccccc"
    property real length: 0

    eulerRotation.x: -90
    scale: Qt.vector3d(0.002, root.length/100, 0.002)
    source: "#Cone"
    opacity: 0.8
    materials: PrincipledMaterial {
        baseColor: root.baseColor
        lighting: PrincipledMaterial.NoLighting
    }
}
