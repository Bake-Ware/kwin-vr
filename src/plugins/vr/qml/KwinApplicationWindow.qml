/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

/** The Application Window contains one non transient window and
 * all its transient windows (menus, popups, other normal windows)
 * arranged as a stack of 3D rectangles.
 */
KwinTransientWindow {
    id: root
    grabHandle: root
    nextComponent: KwinTransientWindowRecursive {
        ppu: root.ppu
        focusControl: root.focusControl
        nextComponent: root.nextComponent
        grabHandle: root.grabHandle
        windowDataModel:  root.windowDataModel
        normalWindowFlexibleBottom: 4
    }
}
