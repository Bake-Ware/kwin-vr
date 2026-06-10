/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Pins HUD overlay placement (VrHudWindow → HudPlacementLogic.js), and the
// #17 fix: a popup/menu must sit strictly closer to the viewer than the HUD
// window it belongs to, flat AND curved, everywhere along the arc.

import QtQuick
import QtTest

import "../../qml/HudPlacementLogic.js" as HudPlacement

TestCase {
    name: "HudPlacement"

    // typical HUD: 1920x1080 at ppu 20
    readonly property real sw: 96
    readonly property real sh: 54

    function fuzzyCompare(a, b, eps, msg) {
        verify(Math.abs(a - b) < eps, (msg || "") + " — expected " + b + ", got " + a)
    }

    // --- lift ladder ---
    function test_surfaceLift() {
        compare(HudPlacement.surfaceLift(0), 0.5)        // root HUD window
        verify(HudPlacement.surfaceLift(1) > HudPlacement.surfaceLift(0), "popup above parent")
        verify(HudPlacement.surfaceLift(2) > HudPlacement.surfaceLift(1), "submenu above popup")
        compare(HudPlacement.surfaceLift(-3), 0.5)       // negative depth clamps to base
    }

    // --- flat branch ---
    function test_flatPlacement() {
        const p = HudPlacement.placeOnHud(0.25, -0.5, sw, sh, 0, 0.5)
        compare(p.x, 24)        // screenNx * surfaceW
        compare(p.y, 27)        // -screenNy * surfaceH
        compare(p.z, 0.5)       // base lift
        compare(p.yawDeg, 0)
    }
    function test_flatPopupCloserThanParent() {
        const parent = HudPlacement.placeOnHud(0.1, 0.1, sw, sh, 0, HudPlacement.surfaceLift(0))
        const popup = HudPlacement.placeOnHud(0.1, 0.1, sw, sh, 0, HudPlacement.surfaceLift(1))
        verify(popup.z > parent.z, "popup lifted toward viewer (+z) in flat mode")
    }

    // --- curved branch ---
    // Center of a curved HUD must match the flat z (continuity at the seam
    // the old code had: z(angle=0) == lift).
    function test_curvedCenterContinuity() {
        const p = HudPlacement.placeOnHud(0, 0, sw, sh, 1.2, 0.5)
        fuzzyCompare(p.x, 0, 1e-9, "centered window x")
        fuzzyCompare(p.z, 0.5, 1e-9, "center of arc keeps flat lift")
        fuzzyCompare(p.yawDeg, 0, 1e-9, "no yaw at arc center")
    }
    // Radial lift: distance from the cylinder axis must shrink by exactly
    // the lift delta, at the center AND at the arc edge (a z-only offset
    // would fail the edge case — that asymmetry was part of #17).
    function test_curvedLiftIsRadial_data() {
        return [
            { tag: "arc center", nx: 0.0 },
            { tag: "arc edge", nx: 0.5 },
            { tag: "off-center", nx: -0.3 },
        ]
    }
    function test_curvedLiftIsRadial(d) {
        const theta = 1.2
        const radius = sw / theta
        const l0 = HudPlacement.surfaceLift(0)
        const l1 = HudPlacement.surfaceLift(1)
        const parent = HudPlacement.placeOnHud(d.nx, 0, sw, sh, theta, l0)
        const popup = HudPlacement.placeOnHud(d.nx, 0, sw, sh, theta, l1)
        // Cylinder axis sits at (0, y, radius) in hudNode-local coords.
        const dParent = Math.hypot(parent.x - 0, parent.z - radius)
        const dPopup = Math.hypot(popup.x - 0, popup.z - radius)
        fuzzyCompare(dParent - dPopup, l1 - l0, 1e-9,
                     "popup exactly one lift step closer to the axis (" + d.tag + ")")
        // Same tangent yaw regardless of lift
        fuzzyCompare(popup.yawDeg, parent.yawDeg, 1e-9, "lift must not change yaw")
    }
    // Yaw follows the tangent: edges of a 1.2 rad arc yaw by ±0.6 rad.
    function test_curvedYaw() {
        const left = HudPlacement.placeOnHud(-0.5, 0, sw, sh, 1.2, 0.5)
        const right = HudPlacement.placeOnHud(0.5, 0, sw, sh, 1.2, 0.5)
        fuzzyCompare(left.yawDeg, 0.6 * 180 / Math.PI, 1e-9, "left edge yaw")
        fuzzyCompare(right.yawDeg, -0.6 * 180 / Math.PI, 1e-9, "right edge yaw")
    }
    // Mirror symmetry across the arc center.
    function test_curvedMirrorSymmetry() {
        const l = HudPlacement.placeOnHud(-0.25, 0, sw, sh, 1.2, 0.5)
        const r = HudPlacement.placeOnHud(0.25, 0, sw, sh, 1.2, 0.5)
        fuzzyCompare(l.x, -r.x, 1e-9, "x mirrors")
        fuzzyCompare(l.z, r.z, 1e-9, "z equal")
        fuzzyCompare(l.yawDeg, -r.yawDeg, 1e-9, "yaw mirrors")
    }
    // Vertical mapping is independent of curvature.
    function test_yIndependentOfCurvature() {
        const flat = HudPlacement.placeOnHud(0.2, 0.3, sw, sh, 0, 0.5)
        const curved = HudPlacement.placeOnHud(0.2, 0.3, sw, sh, 1.2, 0.5)
        compare(curved.y, flat.y)
    }
}
