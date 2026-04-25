# CurvedPlane — architecture

One primitive: `CurvedPlane`. Everything in the VR scene is a CurvedPlane — windows, snap groups, stacks, free containers, pseudomirrors. Properties drive behaviour, not type checks.

## Primitive

```
CurvedPlane (Node)
├── planeId            string   // unique
├── content            QtObject?// KWin client; null for pure containers
│
│   --- intrinsic state (used when not abducted) ---
├── intrinsicPosition  vector3d
├── intrinsicRotation  quaternion
├── intrinsicSize      size       // in world units
├── intrinsicCurvature real       // arc radians, 0 = flat
│
│   --- children layout ---
├── mode               int        // None | Free | Snap | Stack
├── slots              [Slot]     // ordered list
│
│   --- render hints (rebound on every layout pass) ---
├── renderPosition     vector3d   // pushed by abductor or = intrinsic
├── renderRotation     quaternion
├── renderSize         size
├── renderCurvature    real
│
│   --- decorations ---
└── controlTabVisible  bool
```

```
Slot
├── planeId            string
└── overrides          { curvature?, size?, position? }   // nulled fields fall through to plane intrinsic
```

## Modes

```
None   leaf, no children
Free   children at arbitrary positions on me; offsets stored in slot.overrides.position
Snap   children auto-packed in a row, magnetised. No per-slot position; layout = order
Stack  children cascaded with constant offset. No per-slot position; layout = order
```

## Registry

Single QML object, scene-level singleton.

```
PlaneRegistry
├── register(plane)
├── unregister(planeId)
├── findById(id) -> plane
├── findAbductor(id) -> plane | null    // O(N) scan over all planes' slots
└── removeFromAllSlots(id)               // enforce single-list invariant
```

`addChild(plane, slot)` on any container plane MUST call `registry.removeFromAllSlots(slot.planeId)` first. Single-list invariant.

## Effective state (the rule)

For any plane:

```
abductor = registry.findAbductor(planeId)
if abductor == null:
    renderPosition  = intrinsicPosition
    renderRotation  = intrinsicRotation
    renderSize      = intrinsicSize
    renderCurvature = intrinsicCurvature
else:
    abductor.layout() will write our render* on its layout pass
    we DO NOT read abductor; abductor pushes
```

Detach on next tick → no abductor found → render* = intrinsic*. Plane reasserts itself. No reparenting, no Qt scene-graph dance.

## Layout flow

Each plane owns a `relayout()` that iterates its `slots`, computes per-child render state, writes it to the child:

```
relayout():
  for each slot in slots:
    child = registry.findById(slot.planeId)
    if !child: continue                         // dead reference, skip (gc later)
    transform   = layoutFor(slot, mode)         // mode-specific
    curvature   = slot.overrides.curvature ?? renderCurvature
    size        = slot.overrides.size ?? child.intrinsicSize
    child.renderPosition  = transform.position
    child.renderRotation  = transform.rotation
    child.renderSize      = size
    child.renderCurvature = curvature
    child.relayout()                            // recurse
```

Trigger: any change to my own state (transform, mode, slots, curvature) marks me dirty. Once per frame, dirty planes call `relayout()`.

Top-level (no abductor): nothing pushes my render*. I bind render* to intrinsic*. My `relayout()` still pushes my own children.

## Plane render

```
Node {
    position: renderPosition
    rotation: renderRotation
    
    Loader3D {                   // window content if content !== null
        active: content !== null
        sourceComponent: <CurvedWindowContent (uses CurvedPlaneGeometry, curvature=renderCurvature, size=renderSize)>
    }
    
    // Decorations: control tab, border, etc. Rendered on top of content.
    Loader3D {
        active: controlTabVisible
        sourceComponent: ControlTab { ... }
    }
}
```

Window content = a `Model { geometry: CurvedPlaneGeometry { width, height, curvature } materials: ... }` wrapping the KWin texture. Mirror `VrHudWindow.qml` rendering pattern.

## Drag = abduction by ray

Pickray has its own `slots` list. Single slot at most.

```
grab(plane):
    registry.removeFromAllSlots(plane.planeId)
    pickRay.slots = [{ planeId: plane.planeId, overrides: { position: gripOffset } }]
    pickRay.relayout()                           // pushes plane to ray pose

while held:
    pickRay sceneTransform changes → pickRay.relayout() → plane follows

release(plane):
    pickRay.slots = []
    target = currentSnapTarget                   // null if none under cursor
    if target:
        target.addChild(plane, { /* mode-appropriate slot */ })
    else:
        // plane goes top-level: no abductor, render* = intrinsic*
        // settle in place: write current render* into intrinsic*
        plane.intrinsicPosition = plane.renderPosition
        plane.intrinsicRotation = plane.renderRotation
        // size + curvature reset to intrinsic always (overrides die with the slot)
```

Detach is automatic — `removeFromAllSlots` at grab-start pops the plane from any container.

## Snap mode — 1D row pack with magnetise

Phase-1 layout rule:

```
layoutFor(slot, Snap):
    cumulativeX = 0
    for s in slots up to and including slot:
        if s != slot: cumulativeX += child(s).renderSize.width + KWinVRConfig.snapGap
    centre child at (cumulativeX + slot.size.width/2, 0, 0) in container frame
    rotation = identity
```

Magnetise = remove a child from `slots` and the next layout pass closes the gap. No bisection, no adjacency.

Insertion telegraph: while a plane is grabbed and the ray hovers between two of a Snap container's slots at the right Y range, container shows a thin vertical gap-widening line at the insertion index. On release, `addChild(plane, { insertAt: index })` lands the plane there.

## Stack mode — cascade

Phase-1 layout rule:

```
layoutFor(slot, Stack):
    k = index of slot in slots          // 0 = base
    step = KWinVRConfig.zSurfaceMarginTop
    centre child at (step*k, -step*k, step*k) in container frame
    rotation = identity
```

Promote = move slot to end of list. List order = cascade order; last = top.

## Free mode — user-positioned

```
layoutFor(slot, Free):
    pos = slot.overrides.position ?? Qt.vector3d(0, 0, 0)
    rot = slot.overrides.rotation ?? identity
    centre child there, in container frame
```

User drags a child within a Free container → updates `slot.overrides.position`. Plain drag-out still detaches (registry.removeFromAllSlots).

## Container birth / death

```
on snap commit (drag release onto a snap target):
    if target.mode == None:
        // promote target to be a container around itself + the dropped plane
        wrapper = new CurvedPlane { mode: Snap }
        wrapper.intrinsicPosition = target.renderPosition
        wrapper.intrinsicRotation = target.renderRotation
        wrapper.intrinsicCurvature = target.renderCurvature
        wrapper.addChild(target)
        wrapper.addChild(droppedPlane)
        // target has no abductor → wrapper now abducts target; first relayout repositions
    else if target.mode == Snap:
        target.addChild(droppedPlane)
    else if target.mode == Stack:
        target.addChild(droppedPlane)

on slot removal:
    if container.slots.length == 0:
        registry.unregister(container)
        container destroy
    if container.slots.length == 1:
        // dissolve: the lone child becomes top-level
        lone = container.slots[0].plane
        lone.intrinsicPosition  = lone.renderPosition
        lone.intrinsicRotation  = lone.renderRotation
        container.slots = []
        registry.unregister(container)
        container destroy
```

User-created Free containers (selection prism) follow same dissolution rule: ≤ 1 child → die.

## Selection prism

Right-click + drag in empty space (no plane under cursor).

```
press (no hover):           start prism, anchor1 = ray.scenePosition + ray.forward * D
drag:                       update prism, anchor2 = ray.scenePosition + ray.forward * D
                            render wireframe box between anchor1 and anchor2 at depth D
release with motion:
    captured = registry.allPlanes.filter(p => prism.contains(p.renderPosition))
    if captured.length >= 1:
        free = new CurvedPlane { mode: Free }
        free.intrinsicPosition = prism.centre
        for p in captured:
            offset = p.renderPosition - prism.centre
            free.addChild(p, { overrides: { position: offset } })
release without motion:     fall through to existing right-click radial menu
```

Threshold: motion magnitude > `KWinVRConfig.prismMotionThreshold` (e.g. 0.05m).

## Pseudomirror

Stays as is structurally. Each pseudomirror IS a CurvedPlane with `mode: Free`. Its hosted (screen-state) windows are CurvedPlanes registered as slots of the pseudomirror, each with overrides.position = window's output-coord position.

`client.vr` flips:
- `client.vr = false` → window is a slot of its output's pseudomirror (flat layout, no VR controls)
- `client.vr = true`  → window is removed from pseudomirror's slots, becomes top-level (no abductor) at its last vr position

Pseudomirror does NOT show a control tab on hosted windows. That's the only special-case decoration rule.

## Decorations

Every plane renders its own decoration layer.

```
Window planes (content !== null):
    no border
    control tab: "∿" curvature button (per-window override on Alt+wheel)
    Hidden iff abductor === some pseudomirror.

Container planes (content === null):
    border (thin rect at uvSize bbox)
    control tab: "∿" curvature button + "✕" dissolve button
```

Setting `KWinVRConfig.hideControlTabsOnIdle` (bool, default false) → tabs only visible while plane is hovered or being dragged.

Phase-1: minimal control tab — just a clickable Plasma button stub with the dissolve action wired. Curvature slider deferred.

## Curvature

Window content geometry uses `CurvedPlaneGeometry` (`src/plugins/vr/curvedplanegeometry.cpp`). Bind:

```
geometry: CurvedPlaneGeometry {
    width: renderSize.width
    height: renderSize.height
    curvature: renderCurvature
}
```

`renderCurvature = 0` → effectively flat (same as today). Default global curvature comes from `KWinVRConfig.defaultWindowCurvature` — applied to a plane's `intrinsicCurvature` at construction unless that plane already has a value.

Alt + wheel on a window: `renderCurvature += direction * KWinVRConfig.curvatureScrollStep`, clamped 0..6. Writes to slot.overrides.curvature when abducted, else to intrinsicCurvature.

## File structure

New files:

```
src/plugins/vr/qml/
    CurvedPlane.qml             primitive (Node + props + relayout)
    PlaneRegistry.qml            singleton registry
    CurvedWindowContent.qml      Model + CurvedPlaneGeometry + texture material
    SelectionPrism.qml           wireframe + capture logic
    PlaneControlTab.qml          decoration: dissolve + curvature button
```

Modified:

```
KwinApplicationWindow.qml       wraps content in a CurvedPlane (mode: None)
KwinTransientWindow.qml         strip stackedOnto/stackIndex/preSnapGeom; transients render unchanged
XrScene.qml                     remove WindowSnapManager + telegraphGhost; add PlaneRegistry, prism gesture
Main.qml                        add right-click drag detection (prism)
KwinPseudoOutputMirror.qml      becomes a CurvedPlane (mode: Free)
```

Deleted:

```
src/plugins/vr/qml/WindowSnapManager.qml      entirely
```

## kcfg additions

```xml
<entry name="defaultWindowCurvature" type="Double">
  <label>Default curvature for VR windows</label>
  <default>0.0</default>
  <min>0.0</min><max>6.0</max>
</entry>
<entry name="curvatureScrollStep" type="Double">
  <default>0.1</default>
  <min>0.01</min><max>1.0</max>
</entry>
<entry name="snapGap" type="Double">
  <label>Gap between snapped windows in m</label>
  <default>0.02</default>
</entry>
<entry name="prismMotionThreshold" type="Double">
  <default>0.05</default>
</entry>
<entry name="hideControlTabsOnIdle" type="Bool">
  <default>false</default>
</entry>
```

## Invariants

- Every plane is registered in `PlaneRegistry` from construction to destruction.
- A plane is in at most one `slots` list at any time.
- A plane never reads its abductor; abductor pushes on its layout pass.
- Top-level planes' render* mirrors intrinsic* directly.
- Containers with ≤ 1 slot dissolve next layout pass.
- `client.vr` flip is the only hook into the pseudomirror lifecycle (no parent assignments anywhere).

## Out of scope (phase 1)

- HUD as a CurvedPlane (HUD stays as today)
- Camera/ray as containers (pinning)
- Per-window curvature control tab beyond Alt+wheel
- Curvature slider widgets
- KCM entries
- 2D bin-pack snap (1D row only)
- Output-binding rewrite
- Decoration overhaul (titlebar curving with content, etc.)
