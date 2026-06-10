/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin as KWinC
import org.kde.kwin.vr

QtObject {
    id: root

    required property KwinVrInputDevice kwinInput
    required property KwinVrInputFilter kwinInputFilter
    required property VrHeadScroll headScroll
    required property Xray xray
    // Anything with rayPickAll(pos, dir): XrView or View3D (renderer seam)
    required property QtObject xrView
    required property Node cursor3d

    // == Sub-components ==

    readonly property VrPicking picking: VrPicking {
        xray: root.xray
        xrView: root.xrView
    }

    readonly property VrHoverState hoverState: VrHoverState {
        hoveredObject: root.picking.hoveredObject
    }

    readonly property VrPointerHandler pointerHandler: VrPointerHandler {
        kwinInput: root.kwinInput
        headScroll: root.headScroll
        xray: root.xray
        picking: root.picking
        hoverState: root.hoverState
    }

    readonly property VrWindowManipulation windowManipulation: VrWindowManipulation {
        kwinInput: root.kwinInput
        headScroll: root.headScroll
        xray: root.xray
        picking: root.picking
        pointerHandler: root.pointerHandler
    }

    readonly property VrCursorManager cursorManager: VrCursorManager {
        xray: root.xray
        cursor3d: root.cursor3d
        picking: root.picking
        pointerHandler: root.pointerHandler
        currentMovingResizingWindow: root.pointerHandler.currentMovingResizingWindow
    }

    readonly property VrRayController rayController: VrRayController {
        xray: root.xray
        picking: root.picking
    }

    // == Public interface ==

    // Picking (used by XrScene for HUD)
    readonly property pickResult lastPick: root.picking.lastPick
    readonly property Node hoveredObject: root.picking.hoveredObject
    readonly property Node hoveredGrabHandle: root.picking.hoveredGrabHandle

    // Hover state (used by XrScene for grabDesktop)
    readonly property Node desktopOrDockHovered: root.hoverState.desktopOrDockHovered

    // Window manipulation (used by XrScene and KwinTransientWindow)
    property alias currentMovingResizingWindow: root.pointerHandler.currentMovingResizingWindow

    // Cursor manager (used by XrScene for radial menu visibility check)
    readonly property Node cursorHoverObject: root.cursorManager.cursorHoverObject
    property alias cursorEnabled: root.cursorManager.cursorEnabled
}
