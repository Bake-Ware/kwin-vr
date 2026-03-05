/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin.vr

Item {
    id: root
    property KwinVrInputDevice kwinInput
    property bool clickModeActive: false
    property bool volUpClickDown: false
    property bool volDownClickDown: false

    // Combo detection state
    property int pendingKey: -1
    property bool pendingIsPress: false

    Timer {
        id: comboTimer
        interval: KWinVRConfig.volumeClickComboTimeout
        onTriggered: {
            if (clickModeActive) {
                toggleClick(pendingKey)
            }
            pendingKey = -1
        }
    }

    function handleKey(event, pressed) {
        // Always allow combo detection to work regardless of current mode
        if (event.isAutoRepeat) return false

        let key = event.key
        if (key !== Qt.Key_VolumeUp && key !== Qt.Key_VolumeDown) return false

        if (pressed) {
            if (pendingKey !== -1 && pendingKey !== key) {
                // Second key of combo — toggle clickModeActive, but only enable it if volumeClickEnabled is true
                comboTimer.stop()

                if (clickModeActive) {
                    // Turning OFF click mode -> always allowed
                    clickModeActive = false
                    releaseAll()
                } else {
                    // Turning ON click mode -> only if volumeClickEnabled
                    if (KWinVRConfig.volumeClickEnabled) {
                        clickModeActive = true
                    } else {
                        console.log(Logger.kwinvr, "Volume click mode disabled in settings")
                    }
                }

                pendingKey = -1
                return true // Consume both events of the combo
            }

            if (pendingKey === -1) {
                // First key — start combo window
                pendingKey = key
                comboTimer.restart()

                // Only use click mode if BOTH clickModeActive AND volumeClickEnabled are true
                if (clickModeActive && KWinVRConfig.volumeClickEnabled) {
                    return true // consume, will toggle on timer expiry or same-key-press
                } else {
                    return false // let volume through immediately
                }
            }

            // Same key pressed again while waiting — toggle in click mode if enabled
            if (clickModeActive && KWinVRConfig.volumeClickEnabled) {
                comboTimer.stop()
                toggleClick(key)
                pendingKey = -1
                return true
            }
            return false
        }

        // Release events — only consume in click mode when enabled
        if (clickModeActive && KWinVRConfig.volumeClickEnabled) return true
        return false
    }

    function toggleClick(key) {
        if (key === Qt.Key_VolumeUp) {
            volUpClickDown = !volUpClickDown
            setButton(KWinVRConfig.volUpClickButton, volUpClickDown)
        } else {
            volDownClickDown = !volDownClickDown
            setButton(KWinVRConfig.volDownClickButton, volDownClickDown)
        }
    }

    function setButton(buttonName, down) {
        if (buttonName === "left") kwinInput.leftButton = down
        else if (buttonName === "right") kwinInput.rightButton = down
        else if (buttonName === "middle") kwinInput.middleButton = down
    }

    function releaseAll() {
        if (volUpClickDown) { setButton(KWinVRConfig.volUpClickButton, false) }
        if (volDownClickDown) { setButton(KWinVRConfig.volDownClickButton, false) }
        volUpClickDown = false
        volDownClickDown = false
    }
}
