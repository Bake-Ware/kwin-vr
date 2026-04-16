# Work Surfaces -- Developer Guide

**Branch:** `6.6.3_vr_bake`
**Last updated:** 2026-04-16
**Feature commit:** `efd102d5a9` (work surfaces with UV-projection onto curved primitives)

History: this document was rewritten after the wireframe + UV-projection
overhaul landed. The old cyan-facerect architecture is dead. The
phase-by-phase plan that drove the rewrite is preserved in
`WORK_SURFACES_OVERHAUL.md`.

---

## 1. Feature Overview

Work Surfaces are 3D primitives placed in VR space that act as window
containers. Instead of windows floating freely, users drag them onto a
primitive's region and the window UV-projects onto the shape:

- **Plane, Cube, Pyramid** -- flat regions, window tilts to match face normal.
- **Cylinder** -- body region bends the window into an arc on the cylinder
  surface; caps stay flat.
- **Sphere** -- window deforms into a spherical cap on the front.

Primitives render as **geometry wireframes** only. They are hidden while
inactive (hosting at least one window) and revealed whenever:

1. Any VR window is being dragged anywhere in the scene.
2. The primitive itself hosts zero windows.

Snapped windows stay visible regardless of wireframe state -- they are the
primitive's "skin." Scaling the primitive rescales the wireframe but
**not** the windows; windows keep their world size and occupy a smaller
fraction of the region's UV.

### User flow

1. Middle-click in empty space -> radial menu.
2. `Surface -> Plane / Cube / Cylinder / Pyramid / Sphere`.
3. Primitive appears, placed by `SpaceAllocator3D`, oriented to face the user.
4. Drag any VR window. All primitive wireframes reveal.
5. Ray a region -> window shows a **deformed ghost preview** on it.
6. Release -> snap commits (window reparents to face, UV-projects).
7. To adjust the primitive: middle-click a hosted window -> `Edit Surface`
   -> `TransformGizmo3D` attaches to the primitive.
8. To switch layout: middle-click the primitive itself -> `Layout` submenu.

---

## 2. Architecture

```
                          XrScene.qml
                               |
       +-----------------------+-----------------------+
       |                       |                       |
  outputMirror             appWindow              workSurface
    Repeater3D             Repeater3D              Repeater3D
       |                       |                       |
KwinPseudoOutputMirror   KwinApplicationWindow    inline Node delegate
                               |                       |
                          states: screen /           Loader3D
                          vr / surface               (shape Component by type)
                               |                       |
                          attachedFace,         wsPlane / wsCube /
                          previewFace,          wsCylinder / wsPyramid /
                          regionKind,           wsSphere
                          regionRadius                 |
                               |                       |
                          KwinWaylandSurface3D   WsEdge edges (wireframe) +
                          (Model: swap geometry  WorkSurfaceFace[] (pickable
                          based on regionKind)   proxies + layout host)
```

### Key invariants

- The grabHandle chain ends at `KwinApplicationWindow`. Anything below reads
  region curve params off the grab handle dynamically, so the window tree
  does not need prop-drilling through every intermediate component.
- `WorkSurfaceFace.attachedWindows` is the single source of truth for which
  windows are on a face.
- `WorkSurface` delegate's `hostedWindowCount` is maintained by face callbacks
  (`noteFaceHostedChanged`) -- no polling.
- Snap commit flows through the existing `VrWindowManipulation` grab-release
  path. Preview is a transient property on the grabbed window.

---

## 3. C++ Components

### 3.1 WorkSurfaceModel (`worksurfacemodel.{h,cpp}`)

`QAbstractListModel` owning the list of work surfaces. JSON-persisted to
`~/.config/kwinvr-worksurfaces.json`, debounced at 500ms.

Roles (QML names in parens):

| Role           | Name                | Type          |
|----------------|---------------------|---------------|
| SurfaceIdRole  | `surfaceId`         | QString (UUID)|
| ShapeTypeRole  | `shapeType`         | int enum      |
| PositionRole   | `surfacePosition`   | QVector3D     |
| RotationRole   | `surfaceRotation`   | QQuaternion   |
| ScaleRole      | `surfaceScale`      | QVector3D     |
| FacesRole      | `surfaceFaces`      | QVariantList  |

Invokable API:

```cpp
Q_INVOKABLE QString addSurface(int shapeType);
Q_INVOKABLE void removeSurface(const QString &id);
Q_INVOKABLE void duplicateSurface(const QString &id);
Q_INVOKABLE void updateTransform(const QString &id, const QVector3D &pos,
                                 const QQuaternion &rot, const QVector3D &scale);
Q_INVOKABLE void setFaceLayoutMode(const QString &id, int faceIndex, int mode);
```

Face counts per shape are declared in `WorkSurfaceData::faceCountForShape`:

| Shape    | Faces | Regions                                   |
|----------|-------|-------------------------------------------|
| Plane    | 1     | 1 flat                                    |
| Cube     | 6     | 6 flat (front/back/left/right/top/bottom) |
| Cylinder | 3     | 1 cylinder body + 2 flat caps             |
| Pyramid  | 5     | 4 flat slants + 1 flat base               |
| Sphere   | 1     | 1 spherical patch (front cap)             |

Sphere was 6 patches pre-overhaul; collapsed to 1 for v1.

Note: `wsLog()` writes to `/tmp/kwinvr-worksurface.log` to bypass journald
rate-limiting. Gate or remove before release merge.

### 3.2 Region enums (`worksurfacemodel.h`)

Three QML-exposed namespaces:

```cpp
namespace WorkSurfaceShape  { enum Type { Plane, Cube, Cylinder, Pyramid, Sphere }; }
namespace WorkSurfaceLayout { enum Mode { Masonry, Grid, Stack, Freeform, Cover }; }
namespace WorkSurfaceRegion { enum Kind { FlatRect, CylinderBody, SpherePatch }; }
```

Accessed in QML as `WorkSurfaceShape.Cube`, `WorkSurfaceLayout.Stack`,
`WorkSurfaceRegion.CylinderBody`.

### 3.3 WorkSurfaceLayoutEngine (`worksurfacelayout.{h,cpp}`)

`QML_SINGLETON`. Pure function: `computeLayout(mode, faceSize, windowSizes, activeIndex)`
returns `QVariantList<LayoutSlot>`.

`LayoutSlot`:

```cpp
struct LayoutSlot { QRectF rect; int zOrder; qreal scale; };
```

Modes:

| Mode     | Behavior                                                              |
|----------|-----------------------------------------------------------------------|
| Masonry  | Pack into columns, shortest-column-first. Aspect-preserve scale.      |
| Grid     | Equal cells, auto rows x cols from sqrt.                              |
| Stack    | All at center, `activeIndex` on top. On curved regions: onion radial. |
| Freeform | Center placement, no scaling.                                         |
| Cover    | Active fills region, others hidden (rect=0).                          |

The engine always returns slots in unrolled (flat) face coordinates. Curved
region placement happens in `WorkSurfaceFace.relayout` which maps the flat
slot to an arc / sphere position + rotation.

### 3.4 Curved geometry classes

All three extend `QQuick3DGeometry` with UV-mapped vertex buffers sized in
world units. They are `QML_ELEMENT`s so shape components and
`KwinWaylandSurface3D` can instantiate them inline.

**`CurvedPlaneGeometry`** (pre-existing, pre-overhaul):
Horizontal arc bend. Properties: `width`, `height`, `curvature` (radians),
`segments`.

**`CylinderBodyGeometry`** (new):
Vertical arc slice on a cylinder. Properties: `radius`, `arcAngle`,
`height`, `segments`. At `arcAngle=0` reduces to a flat strip; at `2pi`
wraps full circumference. Vertices at `(r*sin(theta), y, r*cos(theta))` with
outward normals. UVs run `0..1` across the arc (u) and top-to-bottom (v).

**`SpherePatchGeometry`** (new):
Rectangular patch on a sphere. Properties: `radius`, `widthAngle`,
`heightAngle` (both radians), `columns`, `rows`. Centered on `+Z`:
`(r*cos(phi)*sin(theta), r*sin(phi), r*cos(phi)*cos(theta))`. Normals radiate
from origin.

**Design note:** each geometry's origin is the radial center of its curve, so
a Model sitting at its parent region's origin with these geometries
produces a mesh that wraps the parent primitive. This is why the sphere
`WorkSurfaceFace` sits at the primitive root (0,0,0) and not at (0,0,r).

---

## 4. QML Components

### 4.1 `WsEdge.qml`

Thin `#Cylinder` Model drawn between two endpoints, used to build primitive
wireframes. Key properties: `edgeFrom`, `edgeTo`, `thickness`, `edgeColor`.
Rotation is computed via `KwinVrHelpers.rotationBetweenVectors(Qt.vector3d(0,1,0), delta)`.

Used in `XrScene.qml`'s shape Components. Each shape Component declares a
`wireframeVisible` bool; each edge binds `visible` to it. The
`workSurface` delegate Binds `wireframeVisible` to
`xrView.anyWindowDragging || hostedWindowCount === 0`.

### 4.2 `WorkSurfaceFace.qml`

Per-region host. Exposes:

- **Face dimensions:** `faceWidth`, `faceHeight` (world units) -- flat extent
  even for curved regions (arc length for cylinder body, `r * angle` for
  sphere patch). Drives layout engine input.
- **Region descriptor:** `regionKind` (enum), `regionRadius`,
  `regionArcAngle`, `regionPatchWidthAngle`, `regionPatchHeightAngle`.
- **Windowing:** `attachedWindows` (list of KwinApplicationWindow),
  `activeIndex`, `layoutMode`.
- **Pickable proxy:** invisible `#Rectangle` Model, alpha 0, `depthDrawMode: NeverDepthDraw`.
  Exists only to receive ray-pick hits during drag. The visible representation
  is the primitive's wireframe.

Core functions:

- `attachWindow(appWin)` -- adds to list, sets `appWin.attachedFace = self`,
  reparents the window to this face, notifies the delegate via
  `_delegate.noteFaceHostedChanged(+1)`, calls `relayout`.
- `detachWindow(appWin)` -- inverse.
- `relayout()` -- calls the layout engine, then for each window:
  - **FlatRect:** `position = (cx, cy, 0)`, `rotation = identity`.
  - **CylinderBody:** `theta = cx / r`, `position = (0, cy, 0)` plus onion Z
    offset in Stack mode, `rotation = rotationBetweenVectors((0,0,1), (sin(theta),0,cos(theta)))`.
    The window's own curved mesh then bulges to radius r.
  - **SpherePatch:** `phi = cy / r`, `theta = cx / (r * cos(phi))`,
    `position` is the origin plus radial onion offset, `rotation = rotationBetweenVectors((0,0,1), dir)`.

### 4.3 Shape Components (inline in `XrScene.qml`)

Five `Component` blocks instantiated by a `Loader3D` inside the
`workSurfaceRepeater` delegate. Each Component:

1. Declares `property bool wireframeVisible: true`.
2. Draws the primitive's edges as `WsEdge` instances bound to
   `wireframeVisible`.
3. Places one or more `WorkSurfaceFace` children with the appropriate
   `regionKind` and curve parameters.

Specifics:

- **wsPlane** -- 4 rectangle edges, one `WorkSurfaceFace` 60x40.
- **wsCube** -- 12 edges (top + bottom squares + 4 vertical posts), 6 faces
  (front/back 60x40, left/right 60x40, top/bottom 60x60). Cube extent
  60x40x60.
- **wsCylinder** -- top + bottom circles (24 segments each) + 8 vertical
  spines. Body face `faceWidth = 2*pi*30`, `faceHeight = 40`,
  `regionKind = CylinderBody`, `regionRadius = 30`. Two flat caps at y=+/-20.
- **wsPyramid** -- base square (4 edges) + 4 slant edges to apex at y=30.
  4 slant faces 42x24 (FlatRect) + 1 base 60x60.
- **wsSphere** -- 12 longitude meridians (24 segments each) + 5 latitude
  rings at +/-60, +/-30, 0 degrees. Single face at primitive origin:
  `regionKind = SpherePatch`, `regionRadius = 30`,
  `regionPatchWidthAngle = 120deg`, `regionPatchHeightAngle = 80deg`.

### 4.4 `KwinWaylandSurface3D.qml` -- curve swap

The window Model either renders as a flat `#Rectangle` scaled to surface
size, or swaps to a procedurally-generated curved mesh. Selection by region:

```qml
source: root.regionKind === WorkSurfaceRegion.FlatRect ? "#Rectangle" : ""
geometry: {
    switch (root.regionKind) {
    case WorkSurfaceRegion.CylinderBody: return _cylGeom
    case WorkSurfaceRegion.SpherePatch:  return _sphGeom
    default: return null
    }
}
scale: root.regionKind === WorkSurfaceRegion.FlatRect
       ? Qt.vector3d(surfWorldWidth/100, surfWorldHeight/100, 0.01)
       : Qt.vector3d(1, 1, 1)
```

`regionKind` and `regionRadius` are read from `model.grabHandle` dynamically
(KwinApplicationWindow surfaces them). Each surface computes its own curve
from its own `surfaceSize / ppu` world dimensions. Curve arc/angle =
`surfWorldWidth / regionRadius`, clamped to avoid self-overlap.

**Current limit:** subsurfaces (popups, menus) curve per-subsurface using
their OWN local origin as the curve center. They look right individually
but misalign with the parent arc. Acceptable for v1 -- popups are small.

### 4.5 `KwinApplicationWindow` state machine

Three states (mutually exclusive, defined in the XrScene delegate):

| State     | When                                      | Parent               |
|-----------|-------------------------------------------|----------------------|
| `screen`  | `!client.vr`                              | pseudo output mirror |
| `vr`      | `client.vr && attachedFace === null`      | allWindowsGrabHandle |
| `surface` | `client.vr && attachedFace !== null`      | attachedFace         |

Surface state takes precedence (listed first). Region props chain:

```qml
property WorkSurfaceFace attachedFace: null   // hard attachment
property WorkSurfaceFace previewFace:  null   // transient during drag

readonly property var _regionSource: attachedFace ?? previewFace
readonly property int regionKind:     _regionSource?.regionKind   ?? WorkSurfaceRegion.FlatRect
readonly property real regionRadius:  _regionSource?.regionRadius ?? 30
```

`_regionSource` makes the preview deform reuse the same curve swap path as a
hard attachment. On release, `attachedFace` takes over seamlessly.

### 4.6 `VrWindowManipulation.qml` -- drag / preview / snap

Three relevant connections, all grab-scoped:

- **`lookForScreenToPut`** -- on every pick-set update while grabbing:
  1. Try pseudo-output (full-screen hand-back).
  2. Else `rayPickWorkSurfaceFace()` walks pick parents for a
     `WorkSurfaceFace`.
  3. If found, set `_pendingSnapFace`, `_pendingSnapAppWin`, toggle the
     face's `hovered` flag, and set `appWin.previewFace = face` so the window
     deforms live.
  4. If not, `_clearPendingPreview()` resets everything.

- **`snapOnRelease`** -- when the grab ends:
  1. If pending, `previewFace` is cleared (attachedFace about to take over)
     and `attachWindow(appWin)` commits.
  2. Otherwise clear preview and bail.

- **`movingResizingWindowWatcher`** -- when a VR window starts moving,
  if it has `attachedFace` it is first detached via `detachWindowFromSurface`
  before the grab takes over.

### 4.7 `TransformGizmo3D.qml` + radial integration

Gizmo shows when `xrView.selectedNode` is set. Picks on gizmo handles route
to its `beginDrag` / `updateDrag` / `endDrag`. Wiring lives in XrScene
(`onPickHandlePressed` / `onPickHandleReleased` around lines 380-404).

Selection entry points via radial menu (`XrScene.qml` action handler):

| Action         | Selects                                   |
|----------------|-------------------------------------------|
| `transform`    | `radialMenuTargetNode` (any scene node)   |
| `editSurface`  | Parent work surface of hosted window      |
| `confirmGizmo` | Deselect / commit                         |

`editSurface` is offered only when the radial target is a window whose
`attachedFace !== null`. It walks `attachedFace.parent` up to the
`isWorkSurface` delegate Node and makes it the selection target.

### 4.8 Layout mode sub-radial

When the radial target `.isWorkSurface`, the menu adds a `Layout` submenu
(Masonry / Grid / Stack / Freeform / Cover). Selecting a mode:

1. Writes the mode to every face via `workSurfaceModel.setFaceLayoutMode`.
2. Walks the delegate's tree, sets `layoutMode` on each `WorkSurfaceFace`,
   and calls `relayout()`.

Per-face targeting (e.g. Masonry on cube-front, Stack on cube-top) is not
wired yet. Current behavior is "apply to all."

---

## 5. Persistence

File: `~/.config/kwinvr-worksurfaces.json`. Example:

```json
{
  "version": 1,
  "surfaces": [
    {
      "id": "uuid-string",
      "shapeType": 0,
      "position": { "x": 0, "y": 0, "z": -80 },
      "rotation": { "w": 1, "x": 0, "y": 0, "z": 0 },
      "scale":    { "x": 1, "y": 1, "z": 1 },
      "faces":    [ { "layoutMode": 0 } ]
    }
  ]
}
```

- Loaded at `WorkSurfaceModel` construction.
- Save debounced 500ms after any mutation; destructor force-flushes.
- On load, `fromJson` pads / trims the `faces` list to match
  `faceCountForShape(shapeType)`.

**Known bug (pre-overhaul, still open):** the delegate's
`Component.onCompleted` unconditionally calls
`spaceAllocator.findFreePosition` and overwrites the persisted position.
Fix outlined in `WORK_SURFACES_OVERHAUL.md` Section 7. Not yet applied.

---

## 6. Data Flow Examples

### Create surface

```
RadialMenu.onActionTriggered("addCube")
  -> XrScene.addWorkSurface(WorkSurfaceShape.Cube)
  -> WorkSurfaceModel.addSurface(1)
  -> beginInsertRows / endInsertRows
  -> Repeater3D instantiates inline Node delegate
  -> Loader3D loads wsCube Component
  -> Component.onCompleted: spaceAllocator.findFreePosition
  -> workSurfaceModel.updateTransform
```

### Snap window

```
User grabs window (xray.grabbedObject = appWin)
  -> VrPicking emits lastAllPicksChanged each frame
  -> VrWindowManipulation.lookForScreenToPut
     -> rayPickWorkSurfaceFace -> face
     -> appWin.previewFace = face
        -> _regionSource changes
        -> regionKind / regionRadius change
        -> KwinWaylandSurface3D Model swaps #Rectangle -> curved geometry
User releases
  -> xray.grabbedObject = null
  -> snapOnRelease
     -> appWin.previewFace = null
     -> face.attachWindow(appWin)
        -> appWin.attachedFace = face
        -> appWin reparents (state: "vr" -> "surface")
        -> delegate.hostedWindowCount++
        -> relayout()
```

### Wireframe reveal

```
xray.grabbedObject changes
  -> xrView.anyWindowDragging = (grabbedObject !== null)
  -> workSurface.wireframeVisible recomputes
  -> Binding pushes into wsShapeLoader.item.wireframeVisible
  -> each WsEdge in the shape Component toggles visible
```

---

## 7. Known Limits / v2 Work

1. **Subsurface alignment on curved regions.** Each subsurface curves about
   its own local origin. Floats slightly off the primary arc. Fix: compute
   curve in the parent window's coordinate space per-subsurface.
2. **Primitive scale vs window world size.** User spec: scaling the
   primitive should NOT scale the windows. Currently windows inherit
   primitive scale via the parent chain. Fix: apply inverse scale on
   `KwinApplicationWindow` in `surface` state once scale changes become
   common.
3. **Cylinder body pickable proxy** is a flat `188x40` rect at the cylinder
   axis. Works for typical ray angles but will miss side-on picks. Replace
   with a cylinder-shaped invisible proxy Model.
4. **Sphere is 1 region.** Planned: ray-hit picks a dynamic patch around the
   hit point rather than the fixed front cap.
5. **Position persistence overwrite.** See WORK_SURFACES_OVERHAUL.md §7.
6. **Per-face layout targeting.** Layout radial applies to all faces;
   should target the face under the ray invoke point.
7. **Gizmo rotation drag** placeholder -- translation + scale work; rotation
   handle dragging is a TODO inside `TransformGizmo3D.updateDrag`.
8. **`wsLog()` debug file** -- must be gated or removed before release.

---

## 8. File Reference

| File                                                         | Role                                                     |
|--------------------------------------------------------------|----------------------------------------------------------|
| `src/plugins/vr/worksurfacemodel.{h,cpp}`                    | Model, persistence, shape/layout/region enums            |
| `src/plugins/vr/worksurfacelayout.{h,cpp}`                   | LayoutSlot + 5-mode layout engine                        |
| `src/plugins/vr/curvedplanegeometry.{h,cpp}`                 | Horizontal arc mesh (pre-existing)                       |
| `src/plugins/vr/cylinderbodygeometry.{h,cpp}`                | Vertical cylinder arc slice mesh                         |
| `src/plugins/vr/spherepatchgeometry.{h,cpp}`                 | Rectangular sphere patch mesh                            |
| `src/plugins/vr/qml/XrScene.qml`                             | Scene wiring: delegate, shape Components, radial handler |
| `src/plugins/vr/qml/WorkSurfaceFace.qml`                     | Region host: attach / relayout / curve placement         |
| `src/plugins/vr/qml/WsEdge.qml`                              | Cylinder-between-points wireframe helper                 |
| `src/plugins/vr/qml/KwinWaylandSurface3D.qml`                | Window Model with flat / curved geometry swap            |
| `src/plugins/vr/qml/VrWindowManipulation.qml`                | Grab / preview / snap pipeline                           |
| `src/plugins/vr/qml/TransformGizmo3D.qml`                    | Gizmo component (selection target editing)               |
| `src/plugins/vr/qml/RadialMenu.qml` + `RadialMenuNode.qml`   | Radial UI with submenu stack                             |
| `src/plugins/vr/qml/WorkSurface3D.qml`                       | Standalone surface component (not currently used)        |
| `~/.config/kwinvr-worksurfaces.json`                         | Persistence file                                         |
| `/tmp/kwinvr-worksurface.log`                                | Debug log (temporary, gate before release)               |
| `WORK_SURFACES_OVERHAUL.md`                                  | Phased rewrite plan + historical reference               |

---

## 9. Extending

### Add a new primitive shape

1. Add enum value to `WorkSurfaceShape::Type` in `worksurfacemodel.h`.
2. Add face count to `WorkSurfaceData::faceCountForShape`.
3. Add a new `Component` block in `XrScene.qml` following the wsCube pattern:
   wireframe edges (via `WsEdge`) + `WorkSurfaceFace` children with region
   descriptors.
4. Extend the `Loader3D.sourceComponent` switch in the delegate.
5. Add a menu entry under `Surface` in the radial menu.
6. For curved regions: declare `regionKind`, `regionRadius`, curve angles on
   the face and let the existing `KwinWaylandSurface3D` geometry swap + the
   `relayout` placement math handle the rest.

### Add a new region kind

1. Add enum value to `WorkSurfaceRegion::Kind`.
2. Write a new `QQuick3DGeometry` subclass alongside the existing three.
3. Register in `CMakeLists.txt` SOURCES.
4. Extend the `geometry:` switch in `KwinWaylandSurface3D.qml`.
5. Extend the `relayout()` branches in `WorkSurfaceFace.qml` with position
   + rotation math for the new kind.

### Add a new layout mode

1. Add enum value to `WorkSurfaceLayout::Mode`.
2. Implement a `layoutX(faceSize, windowSizes, ...)` method in
   `worksurfacelayout.cpp` that returns a `QList<LayoutSlot>` in unrolled
   face coordinates.
3. Add the case to `WorkSurfaceLayoutEngine::computeLayout`.
4. Add a menu entry to the Layout submenu in `XrScene.qml`.
