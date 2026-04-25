# Impl — bisection on removeMember

**Status:** done (pending VR verification)
**Commits:** this chunk — `work_surfaces: bisection on removeMember`
**Design refs:** [design-bisection](design-bisection.md), [design-lifecycle](design-lifecycle.md)

## Goal

When a member leaves a surface, split the remaining adjacency graph into connected components. Each multi-member component becomes its own surface; singleton components orphan to solo. Preserves curvature; drops edges cleanly across the boundary.

Previously `removeMember` just dropped the member + its edges and dissolved only when ≤1 member remained. Detaching from the middle of a dock chain left stale adjacency — two "islands" sharing one `workSurface` identity, which would misbehave on re-docking.

## What shipped

All inside `WorkSurfaceRegistry.qml`, no other files touched.

- **`_findConnectedComponents(adjacency, members)`** — BFS over the adjacency map (keyed by `_windowKey`), returns an array of arrays of window objects. Unreachable keys are ignored; only window objects that exist in `members` appear in the output (so orphaned edge metadata doesn't pollute the result).
- **`_subsetAdjacency(adjacency, memberWindows)`** — returns a new adjacency object restricted to edges whose both endpoints are in `memberWindows`. Used to split parent adjacency into per-component adjacency.
- **`_pickContinuingComponent(components, surface)`** — largest by member count; tie → component containing `surface.members[0]` (the oldest remaining anchor, which after the member-drop is also the lowest-indexed — design tiebreakers 2 and 3 collapse here because we run after `members.splice`).
- **`removeMember` extended:**
  1. Drop member + touching edges (as before).
  2. Emit `detach` (as before).
  3. If ≤1 member remains → `_dissolve` and return.
  4. Find connected components of remaining adjacency.
  5. If exactly 1 component → done, no split.
  6. Else pick continuing; for each non-continuing component:
     - size-1 → orphan the lone window (no new surface for a singleton).
     - size≥2 → create new surface, inherit `curvature`, reassign members, subset adjacency, emit `bisect`.
  7. Trim continuing surface to its component.
  8. If continuing now has ≤1 member → `_dissolve` (covers T-shape-hub-removed case).

## Files touched

- `src/plugins/vr/qml/WorkSurfaceRegistry.qml`:
  - Header comment updated (no longer "phase 1 no bisection").
  - `surfaceChanged` signal doc updated to include `bisect`.
  - `removeMember` body rewritten.
  - Three new helpers: `_findConnectedComponents`, `_subsetAdjacency`, `_pickContinuingComponent`.

## Edge-case coverage (design checklist)

| Case | Expectation | Behavior |
|------|-------------|----------|
| Linear `[A][B][C]`, A closes | Continues `[B][C]`, no split | ✓ `findCC` returns single component, early return |
| Linear `[A][B][C]`, B closes | Both `{A}` and `{C}` dissolve solo | ✓ 2 singleton components, both orphan, continuing has 1 member → dissolve |
| Linear `[A][B][C][D]`, B closes | `{A}` solo, `{C,D}` continues | ✓ largest component wins as continuing; `{A}` orphans |
| T-shape, hub closes | All 4 dissolve solo | ✓ 4 singletons; continuing = first (size 1), others orphan, continuing dissolves |
| Cycle `[A]-[B]-[C]-[D]-[A]`, A closes | `[B,C,D]` single component | ✓ BFS finds one component, early return |
| Stack root in chain closes | Design defers promotion semantics; `WindowSnapManager.promoteStackMember` handles window-level; bisection sees the surface-level detach after promotion | `removeMember` is called on the leaving window after promotion runs; bisection observes the post-promotion state. Concrete test deferred to autotests chunk |

## Non-goals observed

- No component-centroid position assignment (surface Node transform is unused at this stage — lands with curvature/UV-projection).
- No slide-together animation of remaining UVs.
- No adjacency rerouting when a cycle breaks — dropped edges stay dropped.

## Verification

- Build clean.
- Install + `kwin_wayland --replace` — no QML errors in journal.
- Pending live VR test of: mid-chain detach, T-shape break, re-dock after mid-chain detach (should form clean surface without stale ghost membership).

## Open issues / follow-ups

- **Autotests** remain planned as their own chunk. Needs a Qt Test QML harness (or JS extraction of the graph helpers) — scoped separately in the progress index.
- **Component centroid anchoring** deferred until curvature lands (surface transform has no visual yet).

## Commit history

```
<sha>   work_surfaces: bisection on removeMember
```
