/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma Singleton
import QtQuick

QtObject {
    property LoggingCategory kwinvr: LoggingCategory {
        name: "kwinvr"
    }
}
