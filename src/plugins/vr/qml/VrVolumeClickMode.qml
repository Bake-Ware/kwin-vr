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
        if (!KWinVRConfig.volumeClickEnabled) return false
        if (event.isAutoRepeat) return false

        let key = event.key
        if (key !== Qt.Key_VolumeUp && key !== Qt.Key_VolumeDown) return false

        if (pressed) {
            if (pendingKey !== -1 && pendingKey !== key) {
                // Second key of combo — toggle mode
                comboTimer.stop()
                clickModeActive = !clickModeActive
                if (!clickModeActive) releaseAll()
                console.log(Logger.kwinvr, "Volume click mode:", clickModeActive ? "click" : "volume")
                pendingKey = -1
                return true
            }

            if (pendingKey === -1) {
                // First key — start combo window
                pendingKey = key
                comboTimer.restart()

                if (clickModeActive) {
                    return true // consume, will handle on timer or combo
                } else {
                    return false // let volume through immediately
                }
            }

            // Same key pressed again while waiting — in click mode this is toggle
            if (clickModeActive) {
                comboTimer.stop()
                toggleClick(key)
                pendingKey = -1
                return true
            }
            return false
        }

        // Release events
        if (clickModeActive) return true
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
