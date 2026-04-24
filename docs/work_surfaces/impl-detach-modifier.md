# Impl — plain-drag detach, Shift opts into group

**Status:** done
**Commits:** (pending SHA) — this commit
**Design refs:** [design-drag](design-drag.md)

## Goal

Give the user a way to pull a single window out of a work surface without closing the window. Per user VR testing: plain drag on a member should peel it off (default = individual action); Shift+drag should keep the cluster rigid (opt-in = group). This is reversed from the original `design-drag` spec; [feedback_work_surfaces_drag_default](../../../.claude — actually in agent memory) captures the reasoning.

## What shipped

- New property `_pendingDetach` on `WindowSnapManager`. Set at grab-start when the grabbed window has a `workSurface` AND Shift is NOT held (plain drag).
- Grab-start dispatch now has three branches:
  - Surface member + plain (no Shift) → `_pendingDetach = true`, no reparent (solo drag).
  - Surface member + Shift → `_captureSurfaceDrag` (group-rigid).
  - Not in surface → legacy `_captureStackDrag` fallback (unchanged).
- Grab-release, before `_commitSnap` runs: if `_pendingDetach` is set, call `workSurfaces.removeMember(_lastDragged)` to exit the old surface. Running this ahead of `_commitSnap` means the subsequent `joinOnSnap` inside `_commitSnap` (if the release landed on a snap target) creates/joins cleanly instead of merging the just-detached window back.
- `_pendingDetach` cleared in the release block after all lifecycle calls.

## Files touched

- `src/plugins/vr/qml/WindowSnapManager.qml`:
  - `_pendingDetach` property declared alongside `_surfaceDragMembers`.
  - Grab-start branch reads `Qt.application.keyboardModifiers`.
  - Grab-release runs `workSurfaces.removeMember` before `_commitSnap` when `_pendingDetach`.

## Code refs

- `WindowSnapManager.qml:49-52` — `_pendingDetach` property.
- `WindowSnapManager.qml:~553-567` — Shift detection + capture dispatch (reversed: Shift → group).
- `WindowSnapManager.qml:~570-575` — pre-commit removeMember on plain-drag detach.
- `WindowSnapManager.qml:~589` — `_pendingDetach = false` cleanup.

## Verification

- Build clean.
- Install + `kwin_wayland --replace` — no QML errors in journal.
- Manual test path:
  1. Dock 2 windows into a surface.
  2. Grab one (plain, no modifier), drag away to empty space, release → grabbed is solo; other becomes solo too (dissolve on 1-member).
  3. Dock 3 windows (A-B-C). Plain-grab B, drag away, release in empty space → B is solo. A and C stay in surface but with stale adjacency (no bisection yet — phase-1 known).
  4. Dock A-B. Plain-grab B, drag onto window C, release → B joins C's surface. A becomes solo.
  5. **Shift+grab** now performs the group-rigid drag (whole cluster moves as one).

## Open issues / follow-ups

- **Bisection still missing.** Detach from the middle of a dock chain leaves remaining members in one surface with stale adjacency. Symptoms only show on re-grouping. Next chunk fixes.
- **`Qt.application.keyboardModifiers`** — live property, read at grab-start. Pressing Shift mid-drag doesn't retroactively convert; fine for MVP.
- **Configurable modifier** (`workSurfaceGroupDragModifier` kcfg) deferred. Hardcoded Shift for now; kcfg lands with KCM entries.

## Commit history

```
(pending SHA)   work_surfaces: plain-drag detach, Shift opts into group from surface
```
