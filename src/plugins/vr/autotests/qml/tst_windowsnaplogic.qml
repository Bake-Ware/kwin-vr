/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Pins the dock+stack pair-classification decision table (#14):
// UV → action zones and the landing-pose math, via the pure library
// WindowSnapLogic.js. Covers VOC-SNAP zone + landing behaviors without a
// compositor. Action codes asserted literally — they must stay in sync with
// WindowSnapManager.Action declaration order.

import QtQuick
import QtTest

import "../../qml/WindowSnapLogic.js" as SnapLogic

TestCase {
    name: "WindowSnapLogic"

    readonly property real band: 0.25   // WindowSnapManager edgeBand default

    // --- enum mirror sanity: codes match declaration order in
    // WindowSnapManager.qml `enum Action { None, SnapLeft, SnapRight,
    // SnapAbove, SnapBelow, Stack }` ---
    function test_actionCodes() {
        compare(SnapLogic.ActionNone, 0)
        compare(SnapLogic.ActionSnapLeft, 1)
        compare(SnapLogic.ActionSnapRight, 2)
        compare(SnapLogic.ActionSnapAbove, 3)
        compare(SnapLogic.ActionSnapBelow, 4)
        compare(SnapLogic.ActionStack, 5)
    }

    // --- UV → action zones (v=0 is BOTTOM) ---
    function test_actionFromUv_data() {
        return [
            { tag: "center → Stack",      u: 0.5,  v: 0.5,  a: SnapLogic.ActionStack },
            { tag: "left edge",           u: 0.1,  v: 0.5,  a: SnapLogic.ActionSnapLeft },
            { tag: "right edge",          u: 0.9,  v: 0.5,  a: SnapLogic.ActionSnapRight },
            { tag: "bottom edge (v=0)",   u: 0.5,  v: 0.1,  a: SnapLogic.ActionSnapBelow },
            { tag: "top edge (v=1)",      u: 0.5,  v: 0.9,  a: SnapLogic.ActionSnapAbove },
            // Horizontal zones win at corners (u tested first)
            { tag: "bottom-left corner",  u: 0.1,  v: 0.1,  a: SnapLogic.ActionSnapLeft },
            { tag: "top-right corner",    u: 0.9,  v: 0.9,  a: SnapLogic.ActionSnapRight },
            // Band boundary is exclusive: u == band is NOT in the edge zone
            { tag: "u at band → Stack",   u: 0.25, v: 0.5,  a: SnapLogic.ActionStack },
            { tag: "v at 1-band → Stack", u: 0.5,  v: 0.75, a: SnapLogic.ActionStack },
            { tag: "just inside left",    u: 0.249, v: 0.5, a: SnapLogic.ActionSnapLeft },
        ]
    }
    function test_actionFromUv(d) {
        compare(SnapLogic.actionFromUv(d.u, d.v, band), d.a)
    }

    // --- landing pose: side snaps sit edge-to-edge, size follows the
    // shared axis of the target ---
    function test_landingSnapRight() {
        // target 100x80, dragged 40x60, step 2
        const r = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapRight, 0)
        compare(r.x, 70)        // tw/2 + dw/2
        compare(r.y, 0)
        compare(r.z, 0)
        compare(r.landW, 40)    // keeps own width
        compare(r.landH, 80)    // matches target height
    }
    function test_landingSnapLeft_mirrors() {
        const right = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapRight, 0)
        const left = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapLeft, 0)
        compare(left.x, -right.x)
        compare(left.y, right.y)
        compare(left.landW, right.landW)
        compare(left.landH, right.landH)
    }
    function test_landingSnapAbove() {
        const r = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapAbove, 0)
        compare(r.x, 0)
        compare(r.y, 70)        // th/2 + dh/2
        compare(r.landW, 100)   // matches target width
        compare(r.landH, 60)    // keeps own height
    }
    function test_landingSnapBelow_mirrors() {
        const above = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapAbove, 0)
        const below = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionSnapBelow, 0)
        compare(below.y, -above.y)
        compare(below.landW, above.landW)
        compare(below.landH, above.landH)
    }

    // --- stack cascade: right + down + forward, scaled by stack index,
    // size adopts the target's ---
    function test_landingStackCascade() {
        const first = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionStack, 1)
        compare(first.x, 2); compare(first.y, -2); compare(first.z, 2)
        compare(first.landW, 100); compare(first.landH, 80)

        const third = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionStack, 3)
        compare(third.x, 6); compare(third.y, -6); compare(third.z, 6)
    }
    function test_landingStackIndexFloorsAtOne() {
        const k0 = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionStack, 0)
        const kNull = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionStack, null)
        compare(k0.x, 2)
        compare(kNull.x, 2)
    }

    // --- None → inert zeros ---
    function test_landingNone() {
        const r = SnapLogic.landingPose(100, 80, 40, 60, 2, SnapLogic.ActionNone, 0)
        compare(r.x, 0); compare(r.y, 0); compare(r.z, 0)
        compare(r.landW, 0); compare(r.landH, 0)
    }
}
