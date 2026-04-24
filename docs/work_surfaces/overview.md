# Work Surfaces — overview

## What this feature is

A persistent group concept for the KWin-VR window model. Today (`6.6.3_vr_main` as of the branch point), windows can snap/stack via `WindowSnapManager` (shipped in PR #14, Dock & Stack), but membership is only tracked for stacks via `stackedOnto`. Docked windows share nothing but adjacency — no group identity, no shared state, no rigid drag.

This feature introduces `WorkSurface`, an ephemeral container node that:

- Holds a group of snapped/stacked windows as first-class members.
- Owns shared state (currently: curvature). Future state (transparency, pin, PIP) will hook here too.
- Acts as the rigid transform anchor when the cluster is dragged.
- Is created on the first snap between solo windows, merged when grouped windows snap together, and dissolved when membership drops to 1.

Windows render as UV-projected "chips" laid on the surface's curved manifold — so curvature is a group property by default, with per-window override.

## Scope of phase 1 (`feat/work_surfaces`)

1. `WorkSurface` node + `WorkSurfaceRegistry` lifecycle (create / merge / detach / bisect / dissolve).
2. Curvature rendering on window delegates via `CurvedPlaneGeometry` + three-tier resolution (window override → surface → global default).
3. `defaultWindowCurvature` kcfg entry + KCM spinbox.
4. Group-rigid drag when a member is grabbed (plain drag). Shift+drag = detach single window from the group.
5. Control tab (theme-styled, `PlasmaComponents3`) at top-right of each window and at top-right of each surface bounding box when members > 1. Tab contents: grip icon + curvature button → slider popup. Future-proofed for transparency, PIP, pin.
6. Alt+wheel on a hovered window = quick curvature nudge (bypass popup).
7. Bisection (connected-component split) on member-detach or close. Phase 1 includes this for shakedown — user wants real-layout exercise early.

## Out of scope for phase 1 (deferred to phase 2+)

- Transparency, PIP, pin buttons (tab has design stub).
- Slide-together close-the-gap animation on middle-detach.
- Persist `curvatureOverride` across sessions.
- Snap preview showing surface-level outline instead of per-window.
- Nested surfaces.

## Key terminology

| Term | Meaning |
|------|---------|
| **Surface** | A `WorkSurface` node. Ephemeral group container. |
| **Member** | A window that belongs to a surface via its `workSurface` property. |
| **Adjacency** | Edge list on the surface recording which member is snapped to which on which side (left/right/above/below/stack). Used for bisection topology. |
| **UV projection** | Each member's world pose is derived from the surface's manifold at the member's `surfaceUv` position — member planes lie tangent to the surface curve. Not a true single-mesh composite; visually equivalent. |
| **Window-tab** | Control tab on an individual window. Slider sets that window's `curvatureOverride`. |
| **Group-tab** | Control tab anchored to the surface bounding box (only shown when `members.length > 1`). Slider sets surface curvature AND clears all member overrides. "Whatever is being set is what changes" invariant. |
| **Effective curvature** | `window.curvatureOverride ?? (window.workSurface?.curvature) ?? KWinVRConfig.defaultWindowCurvature` |
| **Group-rigid drag** | Plain drag on any surface member moves the entire surface as one unit — all members reparented under the grabbed window for the duration of the drag, restored on release. |
| **Detach drag** | Shift+drag on a surface member pulls just that window out of the surface. On release in empty space → becomes solo + bisect source. On release over a new snap target → normal snap flow + bisect source. |

## How this is NOT the old pivot

The archived [Pivot: Windows as Surfaces](https://github.com/Bake-Ware/kwin-vr/wiki/Pivot-Windows-as-Surfaces) plan was a lateral-group + `TransformGizmo3D`-based design that got rolled back with the rest of the work-surfaces code path. This feature shares the "surface" noun but nothing else — it's built on top of the surviving Dock & Stack snap model, uses per-window curved geometries (no composite mesh), and has no gizmo. The old plan is dead; don't cherry-pick from it.

## Where the code lives (as of branch start)

- `src/plugins/vr/qml/XrScene.qml` — hosts `WorkSurfaceRegistry`, `WindowSnapManager`, `allWindowsGrabHandle`.
- `src/plugins/vr/qml/WindowSnapManager.qml` — snap intent detection + `_commitSnap` (now calls `workSurfaces.joinOnSnap`).
- `src/plugins/vr/qml/WorkSurface.qml` — the group Node type.
- `src/plugins/vr/qml/WorkSurfaceRegistry.qml` — the lifecycle manager.
- `src/plugins/vr/qml/KwinTransientWindow.qml` — hosts `workSurface` + `curvatureOverride` properties on each window.
- `src/plugins/vr/qml/KwinSurfacedWindow3D.qml`, `KwinDecoratedSurfacedWindow3D.qml` — window delegates (will gain `CurvedPlaneGeometry` and control tabs in later commits).
- `src/plugins/vr/kwinvr.kcfg` — KCM config entries (will gain `defaultWindowCurvature` etc. in later commits).
