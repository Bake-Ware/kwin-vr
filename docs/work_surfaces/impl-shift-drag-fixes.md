# Impl — Shift+drag bugfixes

**Status:** done
**Commits:** this chunk — `work_surfaces: Shift+drag fixes — event.modifiers snapshot + pre-reparent pose`
**Design refs:** [design-drag](design-drag.md)
**Follow-up to:** [impl-group-drag](impl-group-drag.md), [impl-detach-modifier](impl-detach-modifier.md)

## Goal

Two bugs surfaced in VR testing of the plain/Shift dispatch:

1. Shift held at press was never detected. `Qt.application.keyboardModifiers` returns 0 in the VR overlay because the scene doesn't hold global keyboard focus. Result: every drag fell through to `_pendingDetach = true`, so group-rigid drag was unreachable.
2. With group drag fixed, releasing a Shift+drag left the sibling at the pseudomirror instead of its intended scene pose. Position showed first, then rotation (Y-axis flip). Root cause: `setNodePositionFromScene` / `setNodeRotationFromScene` internally read `parentNode()` / `parentItem()` at call time, after we'd already assigned `m.window.parent = m.oldParent`. The parent read races with the QML binding update and returns a transient value.

## What shipped

### Fix 1 — event-level modifier snapshot
- `Main.qml` `MouseArea.onPressed` snapshots `event.modifiers & Qt.ShiftModifier` into `xrView.shiftHeldOnPress`. Same pattern as the existing wheel handler. `event.modifiers` comes from the synthesized `QMouseEvent` the input filter injects, so it's accurate at press time regardless of keyboard focus.
- `XrScene.qml` exposes `shiftHeldOnPress: false` as a plain property.
- `WindowSnapManager` gains `property bool shiftHeld` bound from `xrView.shiftHeldOnPress`. Grab dispatch reads `root.shiftHeld` instead of the unreliable application modifier.

### Fix 2 — pre-reparent pose computation
- `_releaseSurfaceDrag` now computes the target local pose against `m.oldParent`'s current scene transform *before* reparenting, then assigns `parent`, `position`, `rotation` explicitly:
  ```qml
  const newLocalPos = m.oldParent.mapPositionFromScene(scenePos)
  const newLocalRot = KwinVrHelpers.getRotationDelta(
      m.oldParent.sceneRotation, sceneRot)
  m.window.parent = m.oldParent
  m.window.position = newLocalPos
  m.window.rotation = newLocalRot
  ```
- Fallback branch (no `oldParent`) writes the scene pose directly.

## Files touched

- `src/plugins/vr/qml/Main.qml` — press-handler snapshots `event.modifiers` onto `xrView.shiftHeldOnPress`.
- `src/plugins/vr/qml/XrScene.qml` — `shiftHeldOnPress` property, pass-through binding on `WindowSnapManager`.
- `src/plugins/vr/qml/WindowSnapManager.qml`:
  - `shiftHeld` property declaration (replaces per-call read).
  - Dispatch site reads `root.shiftHeld`.
  - `_releaseSurfaceDrag` pose restoration rewritten (pre-reparent map).

## Why not use the helpers?

`KwinVrHelpers.setNodePositionFromScene(node, scenePos)` does `node.position = node.parentNode().mapPositionFromScene(scenePos)`. When we've just assigned `node.parent = oldParent`, `parentNode()` can still return the previous parent (or a transient value) until the next binding flush. Pre-computing against an explicit `oldParent` reference sidesteps the race entirely. Same applies to `setNodeRotationFromScene` / `parentItem()`.

Document this as a sharp edge: the helpers are only safe when the parent is already settled.

## Verification

- Plain drag on surface member → member peels off, sibling stays snapped. (Fix 1 verifies: Shift detection working. Fix 2 not exercised.)
- Shift+drag on surface member → cluster moves rigidly, release at empty space → both members land at scene pose, oriented correctly. (Both fixes verified.)
- Shift+drag across to a new target → group-rigid during drag; on release siblings follow into the new surface. (Working.)

## Open issues / follow-ups

- Helpers `setNodePositionFromScene` / `setNodeRotationFromScene` should either document the parent-race or force a parent binding flush internally. Defer until we see another caller bitten.
- Modifier is still hardcoded Shift; kcfg deferred with KCM entries.

## Commit history

```
<sha>   work_surfaces: Shift+drag fixes — event.modifiers snapshot + pre-reparent pose
```
