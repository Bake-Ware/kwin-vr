/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Pure pair-classification + landing math for WindowSnapManager (#14).
// No QML/scene dependencies — every input is a scalar — so qmltest can pin
// the dock/stack decision table directly (kwinvr-testSnapLogic).
.pragma library

// Mirrors WindowSnapManager.Action (QML enums number in declaration order:
// None, SnapLeft, SnapRight, SnapAbove, SnapBelow, Stack). Keep in sync —
// WindowSnapManager delegates here and exposes these through its enum.
const ActionNone = 0
const ActionSnapLeft = 1
const ActionSnapRight = 2
const ActionSnapAbove = 3
const ActionSnapBelow = 4
const ActionStack = 5

// UV → snap action. UV convention: u=0 left, v=0 at BOTTOM.
// Within edgeBand of an edge → snap to that side (horizontal edges win at
// corners); center → stack.
function actionFromUv(u, v, edgeBand) {
    if (u < edgeBand)     return ActionSnapLeft
    if (u > 1 - edgeBand) return ActionSnapRight
    if (v < edgeBand)     return ActionSnapBelow
    if (v > 1 - edgeBand) return ActionSnapAbove
    return ActionStack
}

// Landing pose in target-local units. tw/th, dw/dh = target/dragged width
// and height (world units); step = cascade/lift unit (zSurfaceMarginTop);
// stackIdx multiplies the stack cascade (1 = first child; 0/null → 1).
// Returns { x, y, z, landW, landH } — offset from target center + final size.
function landingPose(tw, th, dw, dh, step, action, stackIdx) {
    switch (action) {
    case ActionStack: {
        const k = Math.max(stackIdx || 1, 1)
        // Cascade right + down + forward.
        return { x: step * k, y: -step * k, z: step * k, landW: tw, landH: th }
    }
    case ActionSnapRight:
        return { x: tw / 2 + dw / 2, y: 0, z: 0, landW: dw, landH: th }
    case ActionSnapLeft:
        return { x: -(tw / 2 + dw / 2), y: 0, z: 0, landW: dw, landH: th }
    case ActionSnapAbove:
        return { x: 0, y: th / 2 + dh / 2, z: 0, landW: tw, landH: dh }
    case ActionSnapBelow:
        return { x: 0, y: -(th / 2 + dh / 2), z: 0, landW: tw, landH: dh }
    default:
        return { x: 0, y: 0, z: 0, landW: 0, landH: 0 }
    }
}
