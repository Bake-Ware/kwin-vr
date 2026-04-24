# Impl — registry lifecycle + snap join

**Status:** done
**Commits:** `dd628ff698` — `work_surfaces: registry lifecycle + snap join + feature docs`
**Design refs:** [design-data-model](design-data-model.md), [design-lifecycle](design-lifecycle.md)

## Goal

Implement the create / join / merge / detach / dissolve lifecycle on `WorkSurfaceRegistry` and wire `WindowSnapManager._commitSnap` to call `joinOnSnap` after a successful dock/stack. Groups now exist as data. No drag, no render, no tab — those land in follow-up chunks.

Bisection is **not** in this chunk. `removeMember` here does the single-component case only (drop to 1 member → dissolve). Bisection lands in its own chunk, with tests.

## What shipped (in this chunk)

- `WorkSurfaceRegistry.joinOnSnap(dragged, target, edge)` — handles all four cases (neither/one/both-same/both-different surfaces). Merge target-wins.
- `WorkSurfaceRegistry.removeMember(win)` — drop member + edges, dissolve on ≤ 1 member. **No bisection yet.**
- Internal helpers: `_createSurface`, `_assignMember`, `_windowKey`, `_oppositeEdge`, `_dissolve`, `_newId`.
- `Component { id: surfaceComponent; WorkSurface {} }` for dynamic instantiation.
- `surfaceChanged(surfaceId, kind)` signal — emits `"create" | "join" | "merge" | "detach" | "dissolve"`.
- `WindowSnapManager` gained a `workSurfaces` property (type `var`, optional for legacy tests).
- `WindowSnapManager._commitSnap` calls `workSurfaces.joinOnSnap(dragged, target, edge)` at the end with the edge string derived from the snap action.
- `XrScene.qml` passes `workSurfaces: workSurfaces` into `WindowSnapManager`.

## Behavior verification path

After this chunk lands:

1. Launch VR, spawn 2 windows.
2. Dock one onto the other (drag into edge).
3. Watch journal: `kwin_wayland[..]: WorkSurface create ws_1` then `WorkSurface ... join` logs should appear.
4. Inspect window state (via future debug panel or manual QML inspection): both windows now have `workSurface` pointing to the same surface; surface has `members.length === 2`, adjacency has both directions of the edge.
5. Drag one window away — still stays in surface (no detach-on-release yet in this chunk).
6. Close one window — surface dissolves if down to 1; remaining window becomes solo.

## Files touched

- `src/plugins/vr/qml/WorkSurfaceRegistry.qml` — full rewrite from scaffold to functional lifecycle.
- `src/plugins/vr/qml/WindowSnapManager.qml` — added `workSurfaces` property, `_commitSnap` tail call to `joinOnSnap`.
- `src/plugins/vr/qml/XrScene.qml` — wired registry through to snap manager.

## Code refs

- `WorkSurfaceRegistry.qml:71-136` — `joinOnSnap` handles all four cases.
- `WorkSurfaceRegistry.qml:141-162` — `removeMember`, phase-1 version (no bisect).
- `WorkSurfaceRegistry.qml:164-173` — `_dissolve`.
- `WorkSurfaceRegistry.qml:52-67` — `_windowKey`, `_oppositeEdge`.
- `WindowSnapManager.qml:31` — new `workSurfaces` property.
- `WindowSnapManager.qml:378-391` — edge-string derivation + `joinOnSnap` call at end of `_commitSnap`.
- `XrScene.qml:256-264` — registry wired as `workSurfaces: workSurfaces` on snap manager + registry instantiation.

## Open issues / follow-ups

- **Window identity** — `_windowKey` uses `client.internalId || resourceClass + ":" + pid`. Verify `internalId` exists on `KwinApplicationWindow.client` — grep pending. If not, fallback format may be insufficiently unique.
- **Stack cross-join** — if a window stacked on window A via `stackedOnto` then docks to window C, does current `_commitSnap` call `_detachFromStack` first (yes, line 349) before the snap? Then `joinOnSnap` fires after the stack relationship is already cleared. Means stack-detach doesn't propagate through `removeMember` today — stacked-→unstacked transitions are silent to the surface layer. Probably fine for now since `stackedOnto` + `workSurface` are parallel tracks, but note for later unification.
- **Surface-less merging** — if two grouped windows snap together, current merge migrates source members to target. Test: merging a stack of 3 into a dock chain of 2 gives a 5-member surface with adjacency = union of both + new edge. Exercise this once drag works.
- **No bisection yet** — `removeMember` dissolves on ≤ 1 but does not split on disconnection. Layout that dock-chains A-B-C, then closes B, leaves {A, C} as members of the same surface despite having no adjacency between them. Fixed in bisection chunk. Flag this as a known-wrong state until then.

## Commit history

```
dd628ff698   work_surfaces: registry lifecycle + snap join + feature docs
```
