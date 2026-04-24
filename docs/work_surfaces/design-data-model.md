# Design — data model

## `WorkSurface` (QML Node)

File: `src/plugins/vr/qml/WorkSurface.qml`

```qml
Node {
    property string surfaceId    // stable identifier for logging/telemetry
    property real curvature      // group-level curvature (0.0..6.0, same units as hudCurvature)
    property var members         // ordered list of KwinApplicationWindow members
    property var adjacency       // { windowKey: [{ neighbor: windowKey, edge: string }, ...] }
}
```

Ephemeral. Created by `WorkSurfaceRegistry._createSurface()`, destroyed in `_dissolve()` when members drops to ≤ 1. The Node's own transform (position, rotation) acts as the rigid group anchor — members pose relative to it.

`adjacency` is keyed by a window identifier string (see `WorkSurfaceRegistry._windowKey`). Each edge records which direction the neighbor lies relative to the member (`"left" | "right" | "above" | "below" | "stack"`). Needed for bisection's connected-component walk.

## `WorkSurfaceRegistry` (QML Node, singleton-per-scene)

File: `src/plugins/vr/qml/WorkSurfaceRegistry.qml`

Public API:

| Function | Purpose |
|----------|---------|
| `joinOnSnap(dragged, target, edge)` | Called by `WindowSnapManager._commitSnap` after a successful dock/stack. Handles all four cases: neither in surface, one in surface, both in same surface, both in different surfaces (merge, target wins). Returns the resulting surface. |
| `removeMember(win)` | Remove window from its surface. Drops all adjacency edges touching it. If remaining members ≤ 1 → dissolve. (Bisection beyond simple count-drop lands in a later commit.) |

Private:

| Function | Purpose |
|----------|---------|
| `_createSurface()` | Instantiate via `surfaceComponent.createObject(root, { surfaceId: _newId() })`. |
| `_assignMember(surface, win, neighbor, edge)` | Add to `members`, set `win.workSurface`, extend `adjacency` with the bidirectional edge (if neighbor provided). |
| `_windowKey(w)` | Stringify a window identity. Uses `client.internalId` if available, else `resourceClass + ":" + pid`. |
| `_oppositeEdge(edge)` | left↔right, above↔below, stack↔stack. |
| `_dissolve(s)` | Clear surface refs on any stragglers, `destroy()` the surface, emit `surfaceChanged(id, "dissolve")`. |

Signal: `surfaceChanged(surfaceId, kind)` where kind ∈ `"create" | "join" | "merge" | "detach" | "dissolve"`. Used for debug logging today; future telemetry / UI state invalidation can subscribe.

## Per-window additions (on `KwinTransientWindow`)

File: `src/plugins/vr/qml/KwinTransientWindow.qml`

```qml
property var workSurface: null          // null when solo
property real curvatureOverride: NaN    // NaN → follow surface/default chain
```

NaN sentinel chosen because `real` can't be null — matches QML numeric conventions. Check with `isNaN(w.curvatureOverride)` before reading.

Existing properties retained for phase-1 compat: `stackedOnto`, `stackIndex`, `preSnapGeom`. Stacks still use `stackedOnto` for cascade index logic; `workSurface` rides alongside as the group-identity layer. This is redundant for stacks but safe — future commits may unify once surface-aware cascade is in.

## Effective curvature resolution

Three-tier fallback (used by window delegate when choosing what to feed `CurvedPlaneGeometry.curvature`):

```
!isNaN(window.curvatureOverride) ? window.curvatureOverride
    : (window.workSurface ? window.workSurface.curvature
        : KWinVRConfig.defaultWindowCurvature)
```

Delegate binds to this expression so changes to any tier propagate live. This is set up in the delegate-curvature commit, not in the data-model commit.

## Why not a singleton QML singleton?

QML singletons (the `pragma Singleton` kind) have initialization-order headaches with scene-hosted nodes. The Registry is instantiated explicitly as a child of `XrScene` and passed to `WindowSnapManager` via property binding. That keeps ownership clear and lets the registry parent to `allWindowsGrabHandle` if we want surfaces to ride the world-grab transform (TBD in drag-semantics design).
