/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import QtQuick3D.Xr

XrView {
    id: xrView
    referenceSpace: XrView.ReferenceSpaceLocal

    onInitializeFailed: (errorString) => {
        console.error("XR Test Failed:", errorString)
        xrTestResult.message = errorString
    }

    xrOrigin: XrOrigin {
        id: xrOrigin
        camera: XrCamera {
            DirectionalLight {}
            KdeKubes {
                position: Qt.vector3d(0, 0, -130)
            }
        }
    }

    environment: SceneEnvironment {
        backgroundMode: SceneEnvironment.Transparent
    }

    DirectionalLight {
        eulerRotation.x: -30
        eulerRotation.y: -70
    }

    FrameAnimation {
        id: testFrameAnimation
        property int frameCount: 0
        running: true
        onTriggered: {
            frameCount++
            if (frameCount >= 60) {
                running = false
                xrTestResult.message = "OK"
            }
        }
    }
}
