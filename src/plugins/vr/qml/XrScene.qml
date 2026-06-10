/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import QtQuick3D.Xr

import org.kde.kwin.vr

/*
 * OpenXR scene root: owns the XR session/view, the XR camera, and XR
 * passthrough (blend). All workspace behavior lives in VrWorkspaceScene —
 * this file should stay a thin shell (see M2 renderer seam).
 */
XrView {
    id: xrView
    onInitializeFailed: (errorString) => KwinVrBridge.xrFailed(errorString);
    onSessionEnded: (errorString) => KwinVrBridge.xrFailed("Session ended")
    referenceSpace: XrView.ReferenceSpaceLocal
    depthSubmissionEnabled: false

    property KwinVrInputDevice kwinInput
    property KwinVrInputFilter kwinInputFilter

    readonly property VrWorkspaceScene workspace: ws

    passthroughEnabled: KWinVRConfig.blend
    environment: SceneEnvironment {
        clearColor: "skyblue"
        backgroundMode: KWinVRConfig.blend ? SceneEnvironment.Transparent : SceneEnvironment.Color
        depthPrePassEnabled: KWinVRConfig.depthPrePassEnabled
        depthTestEnabled: KWinVRConfig.depthTestEnabled
    }

    xrOrigin: XrOrigin {
        VrInputBindings {
            kwinInput: xrView.kwinInput
        }

        camera: XrCamera {
            id: cam
        }
    }

    VrWorkspaceScene {
        id: ws
        camera: cam
        pickingView: xrView
        kwinInput: xrView.kwinInput
        kwinInputFilter: xrView.kwinInputFilter

        blendSupported: true
        blendEnabled: xrView.environment.backgroundMode === SceneEnvironment.Transparent
        onBlendToggleRequested: {
            if(xrView.environment.backgroundMode === SceneEnvironment.Transparent) {
                xrView.environment.backgroundMode = SceneEnvironment.Color
                xrView.passthroughEnabled = false
            } else {
                xrView.environment.backgroundMode = SceneEnvironment.Transparent
                xrView.passthroughEnabled = true
            }
        }
    }
}
