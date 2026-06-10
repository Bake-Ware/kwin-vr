// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick

import org.kde.kwin.vr

/*
 * OpenXR entry point: windowless host Item — XrView renders through the
 * OpenXR runtime, input arrives via KwinVrInputFilter interception.
 * The flat-monitor entry point is MainFlat.qml; both share VrInputSurface
 * and VrWorkspaceScene (M2 renderer seam).
 */
Item {
    id: root

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
        headScroll: xrView.workspace.headScroll
        inputDevice: kwinInput
    }

    VrInputSurface {
        id: inputSurface
        ws: xrView.workspace
        pinchFilter: kwinInputFIlter
    }

    XrScene {
        id: xrView
        kwinInput: kwinInput
        kwinInputFilter: kwinInputFIlter
    }
}
