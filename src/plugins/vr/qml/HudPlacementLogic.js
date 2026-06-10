/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Pure HUD-cylinder placement math for VrHudWindow. Scalar-only inputs so
// qmltest can pin it (kwinvr-testHudPlacement). See issue #17: overlay
// popups/menus used to share their parent's radial depth and z-fought it.
.pragma library

// Radial lift off the HUD plane for a window `transientDepth` levels deep in
// its transient chain (0 = root HUD window, 1 = its popup/menu, 2 = submenu…).
// Each level comes one step closer to the viewer so a popup can never
// z-fight the window it belongs to.
const BASE_LIFT = 0.5
const LIFT_STEP = 0.5

function surfaceLift(transientDepth) {
    return BASE_LIFT + LIFT_STEP * Math.max(transientDepth, 0)
}

// Position on the HUD cylinder (hudNode-local).
// screenNx/screenNy: normalized window-center offset from screen center
// (-0.5..+0.5); surfaceW/surfaceH: HUD plane world size; curvature: total
// cylinder arc in radians (0 = flat); lift: radial lift (surfaceLift()).
// Returns { x, y, z, yawDeg }.
//
// Curved branch places the window on a cylinder CONCENTRIC with the HUD
// plane's, radius reduced by `lift`, so the lift is uniform along the whole
// arc (a plain z offset would shrink toward the edges).
function placeOnHud(screenNx, screenNy, surfaceW, surfaceH, curvature, lift) {
    const y = -screenNy * surfaceH

    if (curvature < 0.001) {
        return { x: screenNx * surfaceW, y: y, z: lift, yawDeg: 0 }
    }

    const t = screenNx + 0.5
    const radius = surfaceW / curvature
    const angle = -curvature / 2.0 + t * curvature
    return {
        x: Math.sin(angle) * (radius - lift),
        y: y,
        z: -Math.cos(angle) * (radius - lift) + radius,
        yawDeg: -angle * 180 / Math.PI,
    }
}
