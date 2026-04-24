# Design — drag semantics

Grab/drag behavior for surface members.

## Modes

**Reversed 2026-04-24:** after VR testing, the default and modifier swapped. Plain drag now targets just the grabbed window; Shift engages group-rigid. Default = individual action, opt-in = group action.

| Gesture | Result |
|---------|--------|
| Plain drag on a surface member | **Detach drag.** Only the grabbed window moves. On release: if over a snap target → normal snap flow (+ bisect source if source still has >1 member); if over empty space → becomes solo (+ bisect source). |
| **Shift** + drag on a surface member | **Group-rigid drag.** Entire surface moves as one. All other members reparented under the grabbed window for the duration, restored on release. |
| Drag on the group-tab handle (surface level) | Always group-rigid, regardless of modifier. The group-tab is the explicit "move the cluster" affordance. |
| Drag on a window-tab handle (window level) | Matches window-body drag — plain = detach, Shift = group. |
| Solo window drag | Unchanged single-window behavior. Shift is a no-op on solo windows until they're in a surface. |

The Shift modifier key is configurable via `workSurfaceGroupDragModifier` kcfg (default `"Shift"`; accepts `"Ctrl" | "Alt" | "Meta"`).

## Implementation pattern

Extends the existing `_captureStackDrag` / `_releaseStackDrag` pair in `WindowSnapManager` ([WindowSnapManager.qml:387-422](../../src/plugins/vr/qml/WindowSnapManager.qml)). The current stack-only logic reparents windows where `w.stackedOnto === grabbed`. Work-surface version reparents all `grabbed.workSurface.members` that aren't `grabbed` itself.

```
_captureSurfaceDrag(grabbed, shiftHeld):
    if !grabbed.workSurface: return         // solo → nothing to capture
    if !shiftHeld: return                   // plain = detach; skip reparent
    for m in grabbed.workSurface.members:
        if m === grabbed: continue
        pose = getRelativePose(grabbed, m)
        oldParent = m.parent
        m.parent = grabbed
        m.position = pose.position
        m.rotation = pose.rotation
        record { window: m, oldParent: oldParent }

_releaseSurfaceDrag:
    for record in captured:
        scenePos = record.window.scenePosition
        sceneRot = record.window.sceneRotation
        record.window.parent = record.oldParent
        setNodePositionFromScene(...)
        setNodeRotationFromScene(...)
```

**Why reparent (not transform-math):** Qt's scene graph auto-applies parent transforms to children. Reparenting under grabbed gives rigid drag for free — no per-frame offset update, no fighting `VrFollowMode` rotations that would otherwise compound.

## Snap-target evaluation during group drag

When dragged is a surface member under group-rigid drag, snap intent evaluation should target other surfaces (or solo windows) **outside** the dragged surface — hitting a sibling of the grabbed window shouldn't register as a snap. Filter in `_scan()`: skip picks where the hit window shares a surface with dragged. Implementation lands in the group-drag commit.

Landing pose math continues to use the dragged window's own bounding rect, not the surface's, for phase 1. Surface-level landing bbox preview is a phase 2 nice-to-have.

## Detach on release (no snap target)

When `xray.grabbedObject` becomes null and:
- `dragged.workSurface !== null` AND
- `snapManager.currentAction === None` (no active snap intent)

→ call `workSurfaces.removeMember(dragged)`. The window exits the surface. If source surface had 2 members, the other becomes solo (dissolve). If source had 3+, bisection runs.

For plain (non-Shift) group drag where no snap target was hit: surface has moved as a whole, no structural change, no removeMember call.

For Shift-held detach drag with no snap: only dragged removed.

## Interaction with the existing stack logic

Phase 1 keeps `stackedOnto` / `stackIndex` working as before. The surface layer rides alongside:
- A stack is also a surface (every stack member has both `stackedOnto = parent_stack_window` and `workSurface = S`).
- Stack-rooted drag (pre-existing) still uses `_captureStackDrag`. Surface drag (new) adds a superset path. At commit boundary we either collapse the two into one `_captureSurfaceDrag` path that handles both, or keep both active and ensure they don't double-reparent (use a marker on members to avoid re-parenting a window already captured).

TBD at implementation: how to unify without regressing stack cascade behavior. Decision captured in the group-drag impl doc once written.

## Commits that will touch this

- `work_surfaces: group-rigid drag` — _captureSurfaceDrag + _releaseSurfaceDrag, filter same-surface hits in _scan.
- `work_surfaces: detach modifier` — read Shift state on grab start, skip reparent if held.
- `work_surfaces: detach on release` — wire removeMember into the grab-release path.
- `work_surfaces: close handling` — hook window-close signal to call removeMember.
