/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// qmltest harness for every tst_*.qml under autotests/qml/ — the pure-logic
// QML/JS libraries (WindowSnapLogic.js, HudPlacementLogic.js, …). Run with
// `-platform offscreen` so no display is needed.

#include <QtQuickTest/quicktest.h>

QUICK_TEST_MAIN(kwinvrqmllogic)
