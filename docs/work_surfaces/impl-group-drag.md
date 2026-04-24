# Impl — group-rigid drag

**Status:** done
**Commits:** `83c7371928` — `work_surfaces: group-rigid drag — reparent surface members on grab`
**Design refs:** [design-drag](design-drag.md)

## Goal

When the user grabs any member of a `WorkSurface`, the whole cluster drags as one rigid unit. Technique mirrors the existing stack-root reparent pattern (`_captureStackDrag` / `_releaseStackDrag`), extended to walk `workSurface.members` instead of `stackedOnto` siblings.

This chunk is the "plain drag = group-rigid" half of the drag design. Shift modifier (detach drag) and detach-on-release-without-snap-target are separate chunks.

## What shipped

- New property `_surfaceDragMembers` on `WindowSnapManager` — mirrors `_stackDragMembers` for the surface-aware capture path.
- `_captureSurfaceDrag(grabbed)` — reparents every other member of `grabbed.workSurface` under `grabbed`, saving old parent + relative pose. Skips if grabbed is solo.
- `_releaseSurfaceDrag()` — restores each captured member's original parent and scene pose.
- Grab-start routing in `_grabWatcher`: if grabbed has `workSurface` → `_captureSurfaceDrag`. Otherwise → legacy `_captureStackDrag` (still needed for stacks that existed before surface-joining).
- Grab-release in `_grabWatcher`: calls both `_releaseStackDrag()` and `_releaseSurfaceDrag()`. Each is a no-op if its list is empty.

## Files touched

- `src/plugins/vr/qml/WindowSnapManager.qml`:
  - New property at line 45 (`_surfaceDragMembers`).
  - New functions `_captureSurfaceDrag` + `_releaseSurfaceDrag` after the existing stack release pair.
  - Grab-start branch selects capture path by `workSurface` presence.
  - Grab-release calls both release functions.

## Code refs

- `WindowSnapManager.qml:46-48` — `_surfaceDragMembers` property definition.
- `WindowSnapManager.qml:~427-460` (after build) — `_captureSurfaceDrag` + `_releaseSurfaceDrag`.
- `WindowSnapManager.qml:~510-520` — grab-start dispatch.
- `WindowSnapManager.qml:~530-540` — grab-release dual call.

## Verification

- Build clean (`cmake --build . --target vr`).
- Install + `kwin_wayland --replace` — kwin up, no QML errors in `journalctl --user -u plasma-kwin_wayland.service`.
- Manual test path (user side):
  1. Spawn 2+ windows in VR.
  2. Dock one to another (snap confirms `joinOnSnap` → WorkSurface create log).
  3. Grab either window and drag.
  4. Expected: the other dock member follows rigidly. Snap target preview on a third window should still work (non-surface hit).
  5. Release in empty space: cluster lands where cursor is. Members stay in surface (detach-on-release is a later chunk).
  6. Stack windows also carried along, since stacks are surface members too after `joinOnSnap`.

## Open issues / follow-ups

- **Stack member re-parent after stack detach:** When a non-root stack member is grabbed, `_detachFromStack(now)` fires before capture (existing line ~509). It clears `stackedOnto` but the window is still a surface member, so surface capture correctly carries the remaining stack siblings. The surface adjacency edges for the detached stack relationship are stale until the next commit (`joinOnSnap` only adds edges; no detach-path maintenance yet).
- **`_commitSnap` writes to grabbed's pose during drag-end:** because members are parented under grabbed at that time, their scene pose follows grabbed's new pose. After `_releaseSurfaceDrag`, scene positions are captured and re-set on the restored parent. This works for current allWindowsGrabHandle-parented topology; revisit once surfaces host their own members directly (UV projection chunk).
- **No scan filtering yet:** `_scan` doesn't exclude same-surface hits when evaluating snap intent. Grabbing one dock sibling while dragging "over" another sibling could falsely register a snap intent. Filter in the next chunk alongside detach modifier, since both touch the same hot path.
- **Solo-grab fallback** still uses `_captureStackDrag` for stacks not yet in a surface. Once every stack is routed through `joinOnSnap` (it is, in `_commitSnap`), legacy stacks from prior sessions would be the only exposed case — rare. Keep fallback for safety; remove in phase 2 cleanup.

## Commit history

```
83c7371928   work_surfaces: group-rigid drag — reparent surface members on grab
```
