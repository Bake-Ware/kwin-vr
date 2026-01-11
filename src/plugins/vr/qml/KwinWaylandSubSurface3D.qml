/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin.vr

/* A wayland subsurface as a 3D rectangle */
KwinWaylandSurface3D {
    id: root
    /* this property contains window relative 2D space coordinates (Y grows down):
       Offset from the parent surface, from its top left point */
    readonly property point subsurfacePosition: this.surface?.subSurface.position ?? Qt.point(0,0)
}
