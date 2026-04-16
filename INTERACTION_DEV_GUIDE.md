# KWin-VR Interaction System — Developer Guide

This document covers the interaction model, selection system, transform gizmos,
window snapping, and HUD overlay as implemented across this session's work.

---

## 1. Input Flow

All VR input routes through a single `MouseArea` in `Main.qml` which receives
events from `KwinVrInputDevice` via `KwinVrInputFilter`. The press handler
has strict priority ordering:

```
onPressed priority:
  1. Super+Click         → selectObjectAtCursor() (toggle gizmo)
  2. Both-click (L+R)    → selectObjectAtCursor() (toggle gizmo)
  3. Release if grabbed   → cancel current grab
  4. Gizmo handle click  → start gizmo drag
  5. Meta+Click          → grabDesktop()
  6. Work surface face   → trySelectWorkSurface() (HUD bar)
  7. Empty space click   → grabAllIfEmptySpace() (grab everything)
  8. Radial menu         → fallback
```

Key state tracking in `Main.qml`:
- `heldButtons` (int) — bitwise button state for both-click detection
- `emptySpaceGrabbed` (bool) — click+hold on empty = grab all
- `gizmoDragActive` (bool) — gizmo handle being dragged
- `bothClicked` (bool) — suppress release handling after both-click/Super+click

### Scroll Behavior

`scrollGrab()` in `XrScene.qml` works on ANY grabbed object — windows, surfaces,
mirrors, or the entire workspace (`allWindowsGrabHandle`). Pushes/pulls along
the ray via `pickRay.grabMoveClamped()`.

---

## 2. Selection System

Two parallel selection mechanisms coexist:

### selectedSurfaceId (string) — HUD bar controls
- Set by single-clicking a `WorkSurfaceFace`
- Shows the 6-button HUD control bar (Grab, Face, Scale+/-, Del, Dup)
- Drives `WorkSurfaceFace.selected` via delegate binding

### selectedNode (Node) — Universal gizmo selection
- Set by **Super+Click** or **both-click** (L+R simultaneously)
- **Toggles**: clicking already-selected object deselects it
- Works on any scene object: windows, work surfaces, screen mirrors
- Dynamically creates `TransformGizmo3D` parented to the selected node

Selection logic in `selectObjectAtCursor()`:
1. Walk `lastAllPicks` in distance order
2. Skip objects with `handleId` (gizmo handles)
3. Walk parent chain looking for `grabHandle` property
4. Verify target is under `allWindowsGrabHandle` via `isSceneObject()`
5. Toggle: if target === selectedNode, deselect

### Gizmo Lifecycle

```javascript
onSelectedNodeChanged: {
    // Destroy old
    if (_gizmoInstance) { _gizmoInstance.destroy(); ... }
    // Create new, parented to selectedNode
    if (selectedNode) {
        _gizmoInstance = gizmoComponent.createObject(selectedNode, {
            targetNode: selectedNode,
            isWindow: !!(selectedNode as KwinApplicationWindow),
            isFlatGeometry: isWin || (shapeType === 0)
        })
        // Connect window resize signal for windows
        if (isWin) _gizmoInstance.windowResizeRequested.connect(...)
    }
}
```

Dynamic creation (not Loader3D) because the gizmo must be **parented to the
selected node** so it moves/rotates with it. Loader3D can't reparent its item.

---

## 3. TransformGizmo3D

**File:** `TransformGizmo3D.qml`

Split into three widget groups positioned around the object:

```
                    [Z Rotate - center]
                          ●
  [X Rotate]                              
      ●        ┌─────────────────┐
               │   Selected Obj  │
               │                 │
               └─────────────────┘
                    [Y Rotate]
                       ●
  [Move]                          [Scale]
  ↕ arrows                       □ cubes
  bottom-left                     bottom-right
```

### Handle Layout

| Group | Position | Handles |
|-------|----------|---------|
| Move | `(-groupSpacing, groupOffsetY, groupOffsetZ)` | XYZ arrows (cylinder+cone) |
| Rotate X | `(-groupSpacing*1.3, 0, groupOffsetZ)` | Red disk, center-left |
| Rotate Y | `(0, groupOffsetY*0.6, groupOffsetZ)` | Green disk, center-bottom |
| Rotate Z | `(0, 0, groupOffsetZ)` | Blue disk, dead center |
| Scale | `(groupSpacing, groupOffsetY, groupOffsetZ)` | XYZ cubes + uniform center |

All handles have:
- `depthBias: -200` — render on top of scene geometry
- `pickable: true` (or `pickable: !root.isFlatGeometry` for Z handles)
- `property string handleId` — identifies handle type in pick system

### Context-Aware Behavior

| Property | Effect |
|----------|--------|
| `isWindow: true` | Scale handles emit `windowResizeRequested(dw,dh)` signal instead of setting `scale` property. Connected to `KwinVrHelpers.windowResize()`. |
| `isFlatGeometry: true` | Z translate/scale handles hidden. Z rotation kept. |

### Drag Mechanics

Gizmo handles get **pick priority** — `tryGizmoHandlePress()` scans ALL picks
for `handleId`, not just the closest. This means gizmo handles can be clicked
even when scene geometry is in front.

Continuous drag uses ray-plane intersection each frame:
```
Connections on pickRay.onSceneTransformChanged (enabled: gizmoDragging)
  → KwinVrHelpers.rayPlaneIntersection(ray, dragPlaneCenter, cam.forward)
  → convert to allWindowsGrabHandle space
  → transformGizmo.updateDrag(localPos)
```

Drag plane is camera-facing, fixed at the pick hit position from drag start.

### Rotation

- Linear sensitivity model: `perpDelta.length() * 1.0` degrees per world-unit
- 5° snap increments
- Quaternion built from axis-angle, applied via `KwinVrHelpers.multiplyQuaternions()`

---

## 4. Work Surface Window Snapping

**Snap-on-release** — windows snap to faces only when the grab is released,
not during hover.

### Flow (VrWindowManipulation.qml)

1. During grab: `lookForScreenToPut()` detects face hover
   - Sets `_pendingSnapFace` and `_pendingSnapAppWin`
   - Sets `face.hovered = true` (visual highlight)
2. On grab release: `snapOnRelease` Connections fires
   - Calls `face.attachWindow(appWin)`
   - Clears pending state

### WorkSurfaceFace.qml

Each face provides:
- `attachWindow(appWin)` / `detachWindow(appWin)` — manage attached windows list
- `relayout()` — uses `WorkSurfaceLayoutEngine.computeLayout()` with current layout mode
- `uvToLocalPosition(coords)` — convert ray pick UV to local 3D position
- Visual states: hovered (bright cyan), selected (blue), has windows (green), default (dim cyan)
- `ZStacker` for depth ordering within a face

Layout modes (from `WorkSurfaceLayoutEngine`): Masonry, Grid, Stacking, Freeform, Cover.

---

## 5. Work Surface Shapes

Defined as `Component` instances in `XrScene.qml`, loaded by `Loader3D` in each
work surface delegate:

| Shape | Type | Faces |
|-------|------|-------|
| wsPlane | 0 | 1 front face |
| wsCube | 1 | 6 faces (front/back/left/right/top/bottom) |
| wsCylinder | 2 | 1 wrap face + 2 caps, ghosted cylinder model |
| wsPyramid | 3 | 4 angled faces + 1 base |
| wsSphere | 4 | 6 faces (cube-mapped), ghosted sphere model |

Each face is a `WorkSurfaceFace` instance. Ghosted geometry (`#Cylinder`/`#Sphere`)
uses `"#18ffffff"` semi-transparent material.

---

## 6. HUD System

Camera-pinned content under `hudNode` (child of `XrCamera`):

### HUD Window Filter (C++)

`HudWindowFilter` in `windowmodelfilter.cpp` routes specific window types to HUD:

| Type | Flag |
|------|------|
| Notification, CriticalNotification | `showNotifications` |
| OnScreenDisplay | `showOsd` |
| Dock, Tooltip | `showDock` |
| AppletPopup | `showAppletPopup` |
| Dialog, Splash | `showDialog` |
| Resource class contains "ksmserver"/"logout" | `showDialog` |

Transient children inherit parent's HUD routing. `PrimaryWindowModelFilter`
excludes all HUD types from the 3D scene view.

### HUD Control Bar

6-button bar (`wsControlsBar`) for selected work surfaces:
- Model + Texture sourceItem (Row of Rectangles)
- UV-based click detection in `tryClickWorkSurfaceControls()`
- Buttons: Grab, Face Me, Scale+, Scale-, Delete, Duplicate
- `pickable: visible` — prevents phantom picks when hidden

---

## 7. Pick System Integration

### VrPicking.qml

- `rayPickAll()` each frame via `onSceneTransformChanged`
- `lastAllPicks` — all hits in distance order
- `acceptedPickObject()` — checks `onPick` convention (object can refuse)
- `hoveredObject` — first accepted pick
- `hoveredGrabHandle` — `hoveredObject?.grabHandle`

### Pick Priority Rules

1. **Gizmo handles** (`handleId` property) — scanned across ALL picks, not just closest
2. **Objects with `onPick`** — interactive elements (windows, screens, HUD bar)
3. **WorkSurfaceFace** models — pickable but NO `onPick`, so they don't steal picks from windows
4. **Objects without `onPick`** — accepted by default

### Key Convention

- `onPick(pick): bool` on a Model — accept/refuse being picked
- `grabHandle` property — what to grab when this object is grabbed
- `handleId` property — marks gizmo handles for priority picking
- `parent3d` property — links 2D items to their 3D parent for event routing

---

## 8. Known Issues & Future Work

- **Both-click (L+R) unreliable** through KWin VR input pipeline. Super+Click is the reliable path.
- **Occlusion/click-through bugs** — deferred. Objects behind others can intercept clicks.
- **Position persistence** — work surface delegates always call `spaceAllocator.findFreePosition()` on creation, ignoring saved transforms.
- **Radial menu** — needs visual refresh (arcs, icons) and context-sensitivity per object type.
- **Window-to-face texturing** — windows should map onto face geometry UVs, not float as rectangles.
- **Surface visibility modes** — surfaces should be wireframe-on-idle, highlighted during interaction.
- **Window docking** — windows snapping to each other (deferred).

---

## 9. File Index

| File | Role |
|------|------|
| `Main.qml` | Input handler — mouse/key events, both-click, gizmo drag wiring |
| `XrScene.qml` | Main scene — selection, grab, HUD, work surfaces, gizmo lifecycle |
| `TransformGizmo3D.qml` | Split gizmo — move/rotate/scale handles, drag logic |
| `WorkSurfaceFace.qml` | Per-face window container — snap, layout, visual state |
| `VrWindowManipulation.qml` | Window move/snap-on-release logic |
| `VrPicking.qml` | Per-frame ray picking, onPick convention |
| `Xray.qml` | Grab ray — relative pose tracking, push/pull |
| `VrFocusControl.qml` | Hub connecting picking → pointer → cursor → manipulation |
| `windowmodelfilter.h/cpp` | C++ filters: Primary, HUD, OSD, Transient |
| `WorkSurfaceModel` (C++) | QAbstractListModel — CRUD + JSON persistence |
| `WorkSurfaceLayoutEngine` (C++) | QML_SINGLETON — 5 layout computation modes |
