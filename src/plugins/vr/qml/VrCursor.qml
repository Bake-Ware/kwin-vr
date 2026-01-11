/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

Model {
    id: root
    property color baseColor: "#cccccc"

    source: "#Sphere"
    materials: PrincipledMaterial {
        baseColor: root.baseColor
        lighting: PrincipledMaterial.NoLighting
    }
    opacity: 0.4
    scale: Qt.vector3d(0.02, 0.02, 0.02)
    visible: false
}
