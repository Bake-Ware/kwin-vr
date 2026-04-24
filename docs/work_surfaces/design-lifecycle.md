# Design — lifecycle

Covers the create / merge / join / detach / dissolve / bisect transitions. Bisection has its own deeper doc: [design-bisection](design-bisection.md).

## Create

Trigger: `joinOnSnap(dragged, target, edge)` where both `dragged` and `target` are solo (neither has `workSurface`).

```
1. surface = _createSurface()             // new instance, new surfaceId
2. _assignMember(surface, target, null, null)   // target is anchor, no adjacency yet
3. _assignMember(surface, dragged, target, edge)   // dragged joins with adjacency edge
4. emit surfaceChanged(surfaceId, "create")
```

Order matters: target is added first so it keeps adjacency-empty if no neighbor; dragged joins with the edge.

## Join

Trigger: `joinOnSnap(dragged, target, edge)` where exactly one of dragged/target has a `workSurface`.

The solo window joins the existing surface. Adjacency edge added, `surfaceChanged(id, "join")` emitted.

## Same-surface re-dock

Trigger: `joinOnSnap` where both windows already share the same surface.

Adjacency is updated with the new edge, but membership is untouched. No create, no merge, no join kind emitted.

## Merge

Trigger: `joinOnSnap` where dragged and target have different surfaces.

```
1. Move all source members into target surface (target wins identity, curvature, transform).
2. Concat source adjacency into target adjacency.
3. Add the new edge between dragged and target.
4. Destroy source surface.
5. emit surfaceChanged(target.surfaceId, "merge")
```

**Why target wins:** the user is moving dragged toward target — the spatial anchor is target's current pose. If source won, the cluster would jump to source's anchor on merge, which would visually yank the target window.

## Detach

Trigger: `removeMember(win)`. Called by:

- Snap manager when a grab releases in empty space with no snap target AND the window was a surface member (implementation lands in the "detach-on-release" commit).
- Window close handler (implementation lands in the "close handling" commit).
- Shift+drag release (implementation lands in the "detach modifier" commit).

Phase 1 implementation (current):

```
1. Remove win from surface.members.
2. Drop all adjacency edges touching win (both sides).
3. Clear win.workSurface.
4. emit surfaceChanged(id, "detach")
5. If surface.members.length ≤ 1 → _dissolve(surface)
```

**What's missing (bisection chunk):** after step 4, walk the remaining adjacency to detect disconnected components. If the removal bisected the surface, split into N new surfaces. See [design-bisection](design-bisection.md).

## Dissolve

Trigger: internal, invoked by `removeMember` when members drops to ≤ 1. Also invoked by merge (on the source surface).

```
1. Clear workSurface on any remaining members (should be 0 or 1).
2. emit surfaceChanged(id, "dissolve")
3. Clear members + adjacency for safety.
4. surface.destroy()
```

**Per user:** `curvatureOverride` on the remaining ex-member is **preserved** through dissolution. A user-set override survives because it's a user decision; the default-follow-surface path simply no longer applies.

## State machine summary

```
(solo × 2)  --snap-->  (surface with 2 members)
(solo × 1, surface × 1)  --snap-->  (surface grows by 1)
(surface_A, surface_B)  --snap-->  (surface_A, B dissolved, members migrated)
(surface with N members, one detaches)  --detach-->  (surface with N-1) OR (N-1 + M new surfaces if bisected)
(surface with 1 member)  --always-->  (solo, surface dissolved)
```

## Commits that touch lifecycle

See [impl-scaffold](impl-scaffold.md) and [impl-registry](impl-registry.md). Bisection lifecycle additions will be in a future `impl-bisection.md`.
