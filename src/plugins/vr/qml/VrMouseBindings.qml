/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin.vr

Item {
    id: root
    property KwinVrInputDevice kwinInput

    property var bindingsMap: ({})

    // Toggle state per button — tracks whether the button is currently held down in toggle mode.
    property bool leftToggleState: false
    property bool middleToggleState: false
    property bool rightToggleState: false

    function processList(bindings, callback) {
        for (const binding of bindings) {
            if (binding && binding !== "" && binding !== "none") {
                const normalized = KwinVrHelpers.normalizeKey(binding)
                if (normalized) {
                    bindingsMap[normalized] = callback
                }
            }
        }
    }

    function rebuildMap(): void {
        bindingsMap = {};
        if (KWinVRConfig.leftClickToggle) {
            processList(KWinVRConfig.leftClickBindings, (pressed) => {
                if (pressed) {
                    leftToggleState = !leftToggleState
                    kwinInput.leftButton = leftToggleState
                }
            })
        } else {
            processList(KWinVRConfig.leftClickBindings, (pressed) => { kwinInput.leftButton = pressed })
        }
        if (KWinVRConfig.middleClickToggle) {
            processList(KWinVRConfig.middleClickBindings, (pressed) => {
                if (pressed) {
                    middleToggleState = !middleToggleState
                    kwinInput.middleButton = middleToggleState
                }
            })
        } else {
            processList(KWinVRConfig.middleClickBindings, (pressed) => { kwinInput.middleButton = pressed })
        }
        if (KWinVRConfig.rightClickToggle) {
            processList(KWinVRConfig.rightClickBindings, (pressed) => {
                if (pressed) {
                    rightToggleState = !rightToggleState
                    kwinInput.rightButton = rightToggleState
                }
            })
        } else {
            processList(KWinVRConfig.rightClickBindings, (pressed) => { kwinInput.rightButton = pressed })
        }
    }

    Connections {
        target: KWinVRConfig
        function onLeftClickBindingsChanged() { rebuildMap() }
        function onMiddleClickBindingsChanged() { rebuildMap() }
        function onRightClickBindingsChanged() { rebuildMap() }
        function onLeftClickToggleChanged() {
            if (!KWinVRConfig.leftClickToggle && leftToggleState) {
                kwinInput.leftButton = false
                leftToggleState = false
            }
            rebuildMap()
        }
        function onMiddleClickToggleChanged() {
            if (!KWinVRConfig.middleClickToggle && middleToggleState) {
                kwinInput.middleButton = false
                middleToggleState = false
            }
            rebuildMap()
        }
        function onRightClickToggleChanged() {
            if (!KWinVRConfig.rightClickToggle && rightToggleState) {
                kwinInput.rightButton = false
                rightToggleState = false
            }
            rebuildMap()
        }
    }

    Component.onCompleted: rebuildMap()

    function handleKey(event, pressed) {
        if (event.isAutoRepeat) return false

        let keyStr = KwinVrHelpers.keyToString(event.key, event.modifiers)
        let callback = bindingsMap[keyStr]

        if (callback) {
            callback(pressed)
            return true
        }

        return false
    }
}
