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
        processList(KWinVRConfig.leftClickBindings, (pressed) => { kwinInput.leftButton = pressed })
        processList(KWinVRConfig.middleClickBindings, (pressed) => { kwinInput.middleButton = pressed })
        processList(KWinVRConfig.rightClickBindings, (pressed) => { kwinInput.rightButton = pressed })
    }

    Connections {
        target: KWinVRConfig
        function onLeftClickBindingsChanged() { rebuildMap() }
        function onMiddleClickBindingsChanged() { rebuildMap() }
        function onRightClickBindingsChanged() { rebuildMap() }
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
