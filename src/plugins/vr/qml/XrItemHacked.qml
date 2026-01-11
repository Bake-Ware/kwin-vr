/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick3D.Xr

XrItem {
    pixelsPerUnit: 20
    manualPixelsPerUnit: true
    automaticHeight: true
    automaticWidth: true
    color: "transparent"

    onContentItemChanged: {
        if(contentItem && contentItem.hasOwnProperty("xrItemParent")) {
            contentItem.xrItemParent = this
        }
    }
}
