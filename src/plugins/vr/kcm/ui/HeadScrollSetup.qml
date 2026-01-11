/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root
    spacing: Kirigami.Units.largeSpacing

    HeadScrollBindings {
        Layout.alignment: Qt.AlignHCenter
    }

    HeadScrollSpeed {
        Layout.fillWidth: true
    }
}