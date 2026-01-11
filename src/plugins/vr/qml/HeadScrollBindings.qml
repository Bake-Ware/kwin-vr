/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin.vr

QtObject {
    property var activeButtons: {
        let set = {}
        const bindings = KWinVRConfig.headScrollBindings
        for (let binding of bindings) {
            if (binding === "MouseLeft") set[Qt.LeftButton] = true
            else if (binding === "MouseMiddle") set[Qt.MiddleButton] = true
            else if (binding === "MouseRight") set[Qt.RightButton] = true
            else if (binding === "MouseBack") set[Qt.BackButton] = true
            else if (binding === "MouseForward") set[Qt.ForwardButton] = true
        }
        return set
    }

    property var keyBindings: {
        let set = {}
        const bindings = KWinVRConfig.headScrollBindings
        for (let binding of bindings) {
            if (binding.startsWith("Mouse")) continue
            if (binding === "none" || binding === "") continue
            
            const normalized = KwinVrHelpers.normalizeKey(binding)
            if (normalized) {
                set[normalized] = true
            }
        }
        return set
    }

    function isHeadScrollButton(button): bool {
        return activeButtons[button] === true
    }

    function isHeadScrollKey(key: int, modifiers: int): bool {
        const keyString = KwinVrHelpers.keyToString(key, modifiers)
        return keyBindings[keyString] === true
    }
}
