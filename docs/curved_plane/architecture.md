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
None             leaf, no children
Free             children at arbitrary positions; offsets stored in slot.overrides.position.
                 With stackChildren=true, children also receive a per-rank +Z lift
                 (rank derived from each child's `stackingOrder` property when present,
                 else slot index). Pseudomirrors set this so focused windows rise.
Snap             children auto-packed in a row, magnetised. Layout = slot order.
Stack            children cascaded with constant XYZ offset. Layout = slot order.
OcclusionAware   per Z-class assignment using sticky first-fit on each child's
                 footprint. Non-overlapping siblings share a Z class; overlap forces
                 a new class. (Available as a per-batch helper today; CurvedPlane
                 currently only routes Free / Snap / Stack to it via per-slot calls.)
```

Each mode is a self-contained C++ helper under `src/plugins/vr/layoutmodes/`.
`CascadeMode`, `SnapRowMode`, `FreeMode`, and `OcclusionAwareMode` expose static
helper functions; `LayoutEngine` (QML singleton) wraps them so `CurvedPlane.qml`
can compute one slot's pose at a time. Batch dispatch (whole-container at once)
uses `ILayoutMode` subclasses through `VolumetricStacker`. `StackMode` (the
former `ZStacker` math) is the only batch implementation today; the rest land
when batch callers exist (e.g. layered transient stacks).

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
    if container.slots.length == 1 and container.mode in {Snap, Stack}:
        // a snap row or stack of one isn't a group — dissolve.
        lone = container.slots[0].plane
        lone.intrinsicPosition  = lone.renderPosition
        lone.intrinsicRotation  = lone.renderRotation
        container.slots = []
        registry.unregister(container)
        container destroy
```

Mode-specific dissolution thresholds:
- **Snap, Stack**: a group needs ≥ 2 members. ≤ 1 child → dissolve.
- **Free** (including selection-prism containers): persists with 1 child. Dissolves only when empty.
- **Pseudomirror**: hardware-tied; never auto-dissolves.

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

Each pseudomirror IS a CurvedPlane with `mode: Free`, `_isPseudomirror: true`,
`intrinsicCurvature: 0`, and `stackChildren: true`. Hosted (screen-state)
windows are KwinApplicationWindow CurvedPlanes registered as slots, each with
`overrides.position` driven from the window's `frameGeometry`.

The pseudomirror's `intrinsicCurvature: 0` flows through the abductor curvature
push to all its children — wallpaper and screen-state windows render flat
regardless of `KWinVRConfig.defaultWindowCurvature`. Free-floating (vr=true)
windows have no abductor and use their own intrinsicCurvature, which defaults
to `defaultWindowCurvature`.

`client.vr` flips:
- `client.vr = false` → window is a slot of its output's pseudomirror (flat
  layout, no VR controls). Slot.overrides.position keeps tracking the window's
  frameGeometry.
- `client.vr = true`  → window is removed from pseudomirror's slots, settles
  at its current scene pose into intrinsicPosition / intrinsicRotation, and
  becomes top-level (no abductor).

Pseudomirrors **self-suppress** their own control tab (hardware-tied; not
user-dissolvable) and suppress the control tab on their slot children too.

`stackChildren: true` ranks children by their exposed `stackingOrder` property
(KWin focus order), giving a per-rank +Z lift. Focused windows rise above
unfocused ones — this is how the desktop right-click menu z-lifts above
neighbouring windows on the same monitor.

## Decorations

Every plane renders its own decoration layer.

```
Window planes (content !== null, mode === None):
    no border
    control tab: "∿" curvature button (per-window override on Alt+wheel)
    Hidden iff abductor._isPseudomirror === true.

Container planes (content === null, mode ∈ {Free, Snap, Stack}):
    translucent rectangle behind the front face (gives visible feedback
    that a snap/stack/free container exists)
    control tab: "∿" curvature button + "✕" dissolve button

Pseudomirror planes:
    no own control tab (hardware-tied, not user-dissolvable)
    no border (the VrScreenFrame child handles visual representation)
    control tab also suppressed on slot children
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

QML primitives & infrastructure:

```
src/plugins/vr/qml/
    CurvedPlane.qml             primitive (Node + props + slot layout dispatch)
    PlaneRegistry.qml           singleton registry
    PlaneInteractionManager.qml ray-pick grab → snap / stack / drag dispatch
    CurvedWindowContent.qml     Model + CurvedPlaneGeometry + texture material
    SelectionPrism.qml          wireframe + capture logic
    PlaneControlTab.qml         decoration: dissolve + curvature button
```

C++ layout engine:

```
src/plugins/vr/
    zmargins.h                            ZMargins value type (QML zMargins)
    volumetricstacker.{h,cpp}             batch layout (Mode dispatch via ILayoutMode)
    layoutengine.{h,cpp}                  per-item QML singleton (Layer Q_ENUM, helpers)
    layoutmodes/
        ilayoutmode.h                     batch interface
        stackmode.{h,cpp}                 ZStacker bidirectional Z accumulator
        cascademode.{h,cpp}               diagonal stepX/Y/Z per index
        snaprowmode.{h,cpp}               1D row pack with gap
        freemode.{h,cpp}                  Free stack-Z helper
        occlusionawaremode.{h,cpp}        sticky footprint-max-Z classifier
```

Modified to wrap into the plane system:

```
KwinApplicationWindow.qml       CurvedPlane(mode: None) wrapping embedded
                                KwinTransientWindow rendering
KwinPseudoOutputMirror.qml      CurvedPlane(mode: Free, _isPseudomirror,
                                stackChildren, intrinsicCurvature: 0)
KwinTransientWindow.qml         legacy snap/stack props stripped
KwinWindowThumbnail3D.qml       curvature inherits from nearest
                                CurvedPlane ancestor via parent walk
KwinWaylandSurface3D.qml        same parent-walk pattern
XrScene.qml                     state-machine reparent removed; abductor
                                binding handles screen-state placement
```

Deleted:

```
src/plugins/vr/qml/WindowSnapManager.qml    legacy imperative cascade engine
src/plugins/vr/zstacker.{h,cpp}             renamed to volumetricstacker.*
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
<entry name="occlusionIntraLayerGap" type="Double">
  <label>Z step between occlusion-aware Z classes within a layer</label>
  <default>0.005</default>
</entry>
<entry name="occlusionLayerGap" type="Double">
  <label>Z step between layers when occlusion forces separation</label>
  <default>0.01</default>
</entry>
```

## Layers

`LayoutEngine.Layer` Q_ENUM, sparse values so future modes (Cockpit-style,
Hyprland-mirror, etc.) slot in without renumbering:

```
Content    = 0
Transient  = 100
Overlay    = 200
HUD        = 300
```

Lower value = nearer the plane / further back. Higher = front. Used by
`OcclusionAwareMode` for layer-pass dispatch (when
`VolumetricStacker` batch gains layer-aware iteration; per-slot helpers
don't need it today).

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
