/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick3D
import QtQuick3D.Helpers
import org.kde.kwin.vr

/* KWin's server side window decorations and shadows as two 3D frames */
Node {
    id: root
    required property QtObject client //KWin::Window
    property alias grabHandle: decorationModel.grabHandle
    property real ppu: 20
    property real zScale: 0.02
    property real zOffsetGlobal: 0
    visible: root.client && !root.client.minimized && root.kDecoration

    property QtObject kDecoration: root.client?.decoration

    KwinDecorationModel {
        id: decorationModel
        property Node grabHandle: root
        kDecoration: root.kDecoration
        ppu: root.ppu
        pickable: root.visible
        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier
    }

    KwinShadowModel {
        id: shadow
        shadow: decorationModel.shadow
        width: decorationModel.width
        height: decorationModel.height
        ppu: root.ppu
        depthBias: -root.zOffsetGlobal * KWinVRConfig.depthBiasMultiplier + 1 // slightly behind decoration

        // TODO: the shadow geometry overlaps window geometry.
        // It seems visually correct, because the texture is transparen here,
        // but I don't like the geometry overlap.
        z: -0.05
    }
}
