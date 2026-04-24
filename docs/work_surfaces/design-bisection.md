# Design — bisection

When a member leaves a surface, the remaining adjacency graph may decompose into multiple connected components. Each component becomes its own surface.

## Why phase 1 (per user decision)

The user asked for bisection in the first pass specifically so real layouts exercise the logic early — rather than discovering edge cases in phase 2. Dock chains have ugly topologies (branching, cycles), and the earlier the logic is proven, the less rework later.

## Algorithm

Runs inside `WorkSurfaceRegistry.removeMember(win)` after the adjacency edges touching `win` have been dropped.

```
removeMember(win):
    ... (remove member, drop edges) ...
    if members.length <= 1:
        _dissolve(surface)
        return

    components = _findConnectedComponents(surface.adjacency, surface.members)
    if components.length <= 1:
        return   // no split

    // Pick the "continuing" component — largest, with ties broken by anchor membership.
    continuing = _pickContinuingComponent(components, surface)
    newSurfaces = []
    for comp in components:
        if comp === continuing: continue
        s = _createSurface()
        s.curvature = surface.curvature  // inherit
        for m in comp.members:
            _assignMember(s, m, null, null)
        s.adjacency = _subsetAdjacency(surface.adjacency, comp.members)
        s.position = _componentCentroid(comp.members)  // anchor at geometric center
        newSurfaces.push(s)

    // Trim continuing surface to its component
    surface.members = continuing.members
    surface.adjacency = _subsetAdjacency(surface.adjacency, continuing.members)

    for s in newSurfaces:
        emit surfaceChanged(s.surfaceId, "bisect")
```

`_findConnectedComponents` is a standard BFS/DFS — for each unvisited member, walk outward via adjacency, collect a component, mark all visited.

## Picking the continuing surface

Heuristic:

1. Largest component by member count.
2. On tie: the component that contains the surface's original transform anchor (first-added member).
3. On further tie: the component containing the lowest-indexed member (stable).

Rationale: keeping the largest component as "the surface" minimizes visual disruption — most windows stay anchored, only the smaller splinter gets a new identity.

## Curvature + overrides on bisection

- Each resulting surface (continuing + new) inherits the parent's `curvature`.
- Member `curvatureOverride` values are **preserved**. If a member had an override before bisection, it keeps that override after — the bisection is a group-identity change, not a curvature reset.

## Edge cases to test

These are the shakedown scenarios the user wants exercised. Each should be covered by a unit test in `autotests/` that drives `WorkSurfaceRegistry` directly with mock windows:

### Linear chain, end removed

```
[A][B][C]   — A-B-C chain, A closes
        →   surface continues with [B][C], A's edges removed.
```
Expected: no split, no new surface, members=2, adjacency just {B↔C}.

### Linear chain, middle removed

```
[A][B][C]   — A-B-C chain, B closes
        →   split into {A}, {C}. Both dissolve (solo).
```
Expected: parent surface dissolved, both A and C become solo.

### Longer linear chain, middle removed

```
[A][B][C][D]   — A-B-C-D chain, B closes
            →   split into {A} solo, {C,D} continuing surface.
```
Expected: {A} dissolves. {C,D} continues with curvature inherited.

### T-shape, hub removed

```
   [B]
    |
[A]-[H]-[C]
    |
   [D]

   H closes → {A}, {B}, {C}, {D} each solo (4 components, all singletons).
```
Expected: all members become solo, parent dissolves entirely.

### Stack on dock chain

```
[A][B+stack{B1,B2}][C]   — A, B (with B1/B2 stacked), C
                        — B closes
```
Stack logic promotes B1 to stack root first (existing behavior in `WindowSnapManager.promoteStackMember`). From the surface's POV, B leaves and B1 takes its place in adjacency — or does it?

**Decision TBD at implementation:** when a stack root closes, does the promoted member inherit the root's adjacency edges to dock neighbors? Probably yes — the promoted window occupies the same slot. Test case will lock in the answer.

### Cycle

```
[A]-[B]
 |   |
[D]-[C]
```

A closes. Remaining: B-C-D with edges B↔C, C↔D, D×(B via what was A). If D↔B was never adjacent directly (only A was in between), the graph is now a path B-C-D, single component.

If the layout actually had cycles (possible if user does weird docking?), bisection correctly identifies it as one component.

## Non-goals for phase 1

- **Slide-together animation** when middle detaches — UVs of remaining members stay static per user decision.
- **Rebalancing adjacency** when a cycle is broken — just drop the departed member's edges, don't reroute.
- **Surface anchor relocation** on bisection — new surfaces anchor at component centroid (acceptable for MVP); polish later.

## Commits that will ship this

- `work_surfaces: connected-component helpers` — `_findConnectedComponents`, `_subsetAdjacency`, `_componentCentroid` pure-QML functions.
- `work_surfaces: bisection in removeMember` — wire helpers into the removeMember flow.
- `work_surfaces: bisection autotests` — test file under `autotests/` exercising the edge cases above.
