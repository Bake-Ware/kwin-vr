# Design — UV projection

How windows are positioned on a work surface.

## The "chip on manifold" model

A work surface is conceptually a curved sheet of width × height with a given curvature arc angle. Each member window has a `surfaceUv ∈ [0,1]²` coordinate indicating the normalized position of its center on the surface's manifold.

For each member:

```
pos_local_on_surface  = surface.evaluateManifold(uv.x, uv.y)
rot_local_on_surface  = surface.evaluateTangentFrame(uv.x, uv.y)
```

The window's `position` and `rotation` in surface-local coordinates are then set from these values. The window's own `CurvedPlaneGeometry` uses the same curvature as the surface, so the window chip's curve is tangent-continuous with the surface at the chip's center.

Visually: the surface is one bent canvas, and windows are rectangular patches glued to it in the right spots at the right angles. They bend with the surface, not independently.

## Why not a true single-mesh composite?

A true composite would render one mesh (the surface manifold) with multiple KWin window thumbnails composited onto it as separate UV regions. That requires a custom material / shader that samples N textures based on UV, with per-region source-rect masks. Possible, but:

- Existing `WindowTextureMaterial` and the `KwinDecoratedSurfacedWindow3D` pipeline are per-window — forcing them into a shared surface requires a significant rewrite.
- The "chip on manifold" visual is indistinguishable from true composite at reasonable curvatures and window sizes (< 180° arc, windows larger than the chip's own segment count).
- Performance: N separate draws of curved planes vs 1 draw of a composite plane — draw call difference is negligible for ≤20-ish windows.

If the visual breaks down in practice (seams at extreme curvature, or specific edge cases emerge during testing), revisit. Phase 1 ships with chips.

## UV recomputation — when and how

UV is assigned:
- **On create** — both target and dragged get UVs derived from their world positions projected onto the newly-created surface's bbox. Target typically ends up near `(0.5, 0.5)` (anchor), dragged offset by snap edge direction.
- **On join** — the new member's UV is computed from its world position projected onto the existing surface manifold.
- **On merge** — migrating members keep their scene positions; UVs recomputed via projection onto the target surface's manifold.
- **On detach** — the removed window's UV is cleared (set to null or `(0, 0)` doesn't matter; it's not a member anymore).
- **On middle-detach** — per user decision: other members' UVs stay static. Phase 2 considers "slide together" close-the-gap animation.

Resulting: UV values are stable for a given member once assigned. Surface resizing (e.g. on merge growing the bbox) scales UVs proportionally so members stay in place in world coordinates.

## Surface bounding box

Computed from member positions + sizes:

```
for m in surface.members:
    world_bbox_expand(m.world_pose(), m.client.frameGeometry)
→ surface.width = bbox.width
→ surface.height = bbox.height
```

Recomputed on each member add/remove. UV positions scale accordingly.

## Stack cascade in UV space

Stack members cascade with `off = vector3d(step * k, -step * k, step * k)` (see `WindowSnapManager.qml:218-221`). For phase 1 UV:

- Stack base member has its own UV at its projected position.
- Stack cascade offsets are applied in the surface-tangent frame at the base's UV.
- Cascaded members don't get separate UVs — they're positioned as children of the base's world pose.

This means the whole cascade bends with the manifold as a unit, which is what the user wanted ("cascade along curve").

Trade-off: cascade members don't show up in the adjacency graph as separate nodes, so bisection treats a stack as one unit (remove any member of the stack as a single event from the surface's POV). That matches existing promotion logic where stack siblings stay attached until the root is removed.

## Files touched when this commits

- `src/plugins/vr/qml/WorkSurface.qml` — add `evaluateManifold(u, v)` and `evaluateTangentFrame(u, v)` functions. Use existing `CurvedPlaneGeometry` math.
- `src/plugins/vr/qml/KwinTransientWindow.qml` — add `surfaceUv` property on windows.
- `src/plugins/vr/qml/KwinSurfacedWindow3D.qml`, `KwinDecoratedSurfacedWindow3D.qml` — when `workSurface !== null`, derive local pose from UV projection; otherwise keep existing world-pose behavior.
- `src/plugins/vr/qml/WorkSurfaceRegistry.qml` — in `joinOnSnap` / merge, populate `surfaceUv` on new members.
