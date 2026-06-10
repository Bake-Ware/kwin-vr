/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window

import org.kde.kwin.vr

/*
 * Flat-monitor entry point (M2): a fullscreen window hosting FlatScene.
 * Loaded by KwinVr::start() when displayMode resolves to Flat — see Main.qml
 * for the OpenXR entry point. Interaction grammar is the shared
 * VrInputSurface; mouse motion deflects the ray via the same pointer-offset
 * path as VR, middle-button drag turns the "head".
 */
Window {
    id: flatWindow
    visible: true
    visibility: Window.FullScreen
    /* KWin's internal QPA doesn't size windows from FullScreen visibility
       alone — without explicit geometry the window stays 1x1. */
    width: Screen.width
    height: Screen.height
    color: "black"
    title: "kwin-vr flat workspace"

    KwinVrInputDevice {
        id: kwinInput
        active: true
    }

    KwinVrInputFilter {
        id: kwinInputFIlter
        eventsTarget: inputSurface
        pointerInhibitDelay: KWinVRConfig.pointerInhibitDelay
    }

    KwinInputRemap {
        inputDevice: kwinInput
    }

    VrHeadScrollFilter {
        headScroll: flatScene.workspace.headScroll
        inputDevice: kwinInput
    }

    FlatScene {
        id: flatScene
        kwinInput: kwinInput
        kwinInputFilter: kwinInputFIlter
    }

    VrInputSurface {
        id: inputSurface
        anchors.fill: parent
        ws: flatScene.workspace
        pinchFilter: kwinInputFIlter

        /* Middle-button drag = look around (the flat head). */
        middleDragLook: true
        onLookDelta: (dx, dy) => flatScene.lookBy(dx, dy)
    }
}
