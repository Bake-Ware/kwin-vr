# Work Surfaces -- Developer Guide & Feature Document

**Branch:** `feature/work_surfaces`
**Last updated:** 2026-04-16

> **Heads up:** This file predates the wireframe + UV-projection overhaul
> (2026-04-16). Sections 4c (shape components), 4e (`WorkSurfaceFace`), 6
> (open questions) and 7 (lessons) still describe the cyan-face-rect era.
> Current behavior and the phased refactor that got us here are in
> `WORK_SURFACES_OVERHAUL.md`. Overhaul highlights:
> - `wsFaceRect` and translucent `#Cylinder` / `#Sphere` reference meshes
>   are gone. Each primitive renders as a true geometry wireframe (edges
>   drawn as thin cylinders via `WsEdge.qml`).
> - Wireframes reveal only while a window is being dragged anywhere, plus
>   surfaces hosting zero windows stay wireframe-visible so they remain
>   discoverable.
> - Snapped windows deform to the primitive via `CylinderBodyGeometry` /
>   `SpherePatchGeometry`; flat faces use tilted `#Rectangle` as before.
> - Region descriptors live on `WorkSurfaceFace` (`regionKind`, `regionRadius`,
>   curve params) and drive both the curved mesh swap in `KwinWaylandSurface3D`
>   and placement/rotation math in `WorkSurfaceFace.relayout`.
> - Drag preview: `previewFace` on `KwinApplicationWindow` is bumped by
>   `VrWindowManipulation` while the ray hovers a region so the user sees the
>   deformed ghost; release commits, drag-off reverts.
> - Sphere is a single forward-facing patch (was 6); face counts are otherwise
>   unchanged.

---

## 1. Feature Overview

### What Work Surfaces Are

Work Surfaces are spatial 3D primitives placed in the KWin-VR environment that act
as window containers. Instead of windows floating freely in VR space, users can
organize them onto the faces of geometric shapes -- planes, cubes, cylinders,
pyramids, and spheres. Each face of a primitive can host multiple windows, arranged
automatically by a configurable layout engine.

Think of them as virtual desks, walls, and workstations you build around yourself
in VR space.

### Why They Exist

Free-floating VR windows become disorganized quickly. Work surfaces bring
structure without sacrificing the flexibility of 3D space. The concept maps to
physical-world metaphors: a flat monitor becomes a Plane, a corner desk becomes a
Cube, a surround workstation becomes a Cylinder. The design also supports more
exotic shapes (Pyramid, Sphere) for creative workflows and experimentation.

### User-Facing Concept

From the user's perspective:

1. Open the radial menu (middle-click in empty space)
2. Click **Surface** to open the shape submenu
3. Pick a shape (Plane, Cube, Cylinder, Pyramid, Sphere)
4. The shape appears in VR space with translucent wireframe faces
5. Drag windows onto faces to snap them in place
6. Windows auto-arrange on each face using the active layout mode
7. Surfaces persist across VR sessions

---

## 2. Architecture

### Component Diagram

```
                        XrScene.qml
                            |
            +---------------+----------------+
            |               |                |
    outputMirrorRepeater  appWindowRepeater  workSurfaceRepeater
            |               |                |
  KwinPseudoOutputMirror  KwinAppWindow    Node (inline delegate)
                            |                |
                       3 states:         Loader3D
                       - "screen"            |
                       - "vr"          Shape Component
                       - "surface"     (wsPlane/wsCube/
                                        wsCylinder/wsPyramid/
                                        wsSphere)
                                             |
                                       wsFaceRect (pickable face)
```

### Data Flow: Menu to Rendered Shape

```
RadialMenu.qml          (user clicks "Surface > Plane")
    |
    | onActionTriggered("addPlane")
    v
XrScene.qml              (action handler calls xrView.addWorkSurface)
    |
    | workSurfaceModel.addSurface(WorkSurfaceShape.Plane)
    v
WorkSurfaceModel (C++)   (creates WorkSurfaceData, emits rowsInserted)
    |
    | QAbstractListModel signal
    v
Repeater3D               (instantiates inline Node delegate)
    |
    | Component.onCompleted: spaceAllocator places it, saves transform
    v
Loader3D                  (switches sourceComponent by shapeType)
    |
    v
Shape Component           (e.g. wsPlane: Node containing wsFaceRect instances)
    |
    v
wsFaceRect                (pickable Model with wireframe texture)
```

### The `required property` Lesson

**Critical lesson learned during development:** When a `Repeater3D` delegate is
an external QML component (e.g., `WorkSurface3D.qml`), the delegate and the
component file must agree exactly on `required property` declarations. If the
component also declares properties with the same names as model roles, QML silently
shadows the model-injected values, causing blank/default data.

**The solution adopted:** The delegate is defined **inline** in `XrScene.qml` as a
plain `Node` with `required property` declarations that match the model roles
exactly. The external `WorkSurface3D.qml` file exists but is NOT used as the
delegate. Shape-specific content is loaded via a `Loader3D` that switches on
`shapeType`, keeping the delegate lightweight and avoiding property shadowing.

The external `WorkSurface3D.qml` still exists as a self-contained component with
its own shape definitions and wireframe face component. It could be used if the
`required property` issue is resolved in a future Qt version, or if the delegate
is refactored to explicitly bind properties rather than relying on automatic model
injection.

---

## 3. C++ Components

### 3a. WorkSurfaceModel

**Files:** `worksurfacemodel.h`, `worksurfacemodel.cpp`

A `QAbstractListModel` that owns the list of work surface instances.

#### Roles

| Role enum        | Role name (QML)     | Type         | Description                   |
|------------------|----------------------|--------------|-------------------------------|
| SurfaceIdRole    | `surfaceId`          | QString      | UUID, unique per surface      |
| ShapeTypeRole    | `shapeType`          | int          | WorkSurfaceShape::Type enum   |
| PositionRole     | `surfacePosition`    | QVector3D    | World-space position          |
| RotationRole     | `surfaceRotation`    | QQuaternion  | World-space rotation          |
| ScaleRole        | `surfaceScale`       | QVector3D    | Scale vector                  |
| FacesRole        | `surfaceFaces`       | QVariantList | List of WorkSurfaceFaceData   |

Note: The position/rotation/scale role names are prefixed with `surface` to
avoid collisions with built-in Node properties in QML delegates.

#### CRUD API

```cpp
Q_INVOKABLE QString addSurface(int shapeType);
Q_INVOKABLE void removeSurface(const QString &id);
Q_INVOKABLE void duplicateSurface(const QString &id);
Q_INVOKABLE void updateTransform(const QString &id, const QVector3D &position,
                                 const QQuaternion &rotation, const QVector3D &scale);
Q_INVOKABLE void setFaceLayoutMode(const QString &id, int faceIndex, int layoutMode);
```

- `addSurface`: Creates a new surface with a generated UUID. Initializes the
  correct number of `WorkSurfaceFaceData` entries based on shape type. Returns
  the new ID.
- `duplicateSurface`: Deep-copies a surface with a new ID, offset by
  `(10, 0, 0)` world units so it appears next to the original.
- `updateTransform`: Called from QML when a surface is moved/rotated/scaled.
  Emits `dataChanged` for the transform roles.

#### Persistence

- **File:** `~/.config/kwinvr-worksurfaces.json`
- **Format:**

```json
{
    "version": 1,
    "surfaces": [
        {
            "id": "uuid-string",
            "shapeType": 0,
            "position": { "x": 0, "y": 0, "z": -80 },
            "rotation": { "w": 1, "x": 0, "y": 0, "z": 0 },
            "scale": { "x": 1, "y": 1, "z": 1 },
            "faces": [
                { "layoutMode": 0 }
            ]
        }
    ]
}
```

- **Load:** On construction, reads the JSON file and populates `m_surfaces` via
  `beginResetModel`/`endResetModel`.
- **Save:** Debounced via a 500ms single-shot `QTimer`. Every mutation calls
  `scheduleSave()`. Destructor force-saves if the timer is active.
- **Path creation:** `QDir().mkpath()` ensures the config directory exists.

#### Debug Logging

The model uses a file-based logger (`wsLog()`) that writes to
`/tmp/kwinvr-worksurface.log`. This bypasses journald rate limiting, which was
found to silently drop `console.log` and `qCDebug` messages during rapid
model operations. See Section 7 for details.

#### Shape Enum

```cpp
namespace WorkSurfaceShape {
    enum Type { Plane, Cube, Cylinder, Pyramid, Sphere };
}
```

Exposed to QML as `WorkSurfaceShape.Plane`, etc. via `Q_NAMESPACE` + `QML_ELEMENT`.

#### Face Count per Shape

| Shape    | Face count | Faces                                      |
|----------|------------|--------------------------------------------|
| Plane    | 1          | Single forward-facing                      |
| Cube     | 6          | Front, back, left, right, top, bottom      |
| Cylinder | 3          | Body (front-facing wrap) + 2 caps          |
| Pyramid  | 5          | 4 slanted sides + base                     |
| Sphere   | 6          | 6 patches (cube-sphere projection)         |

### 3b. WorkSurfaceLayoutEngine

**Files:** `worksurfacelayout.h`, `worksurfacelayout.cpp`

A `QML_SINGLETON` that computes window positions within a rectangular face region.

#### API

```cpp
Q_INVOKABLE QVariantList computeLayout(int layoutMode, const QSizeF &faceSize,
                                       const QVariantList &windowSizes,
                                       int activeIndex = 0);
```

Takes `QVariantList` of `QSizeF` for cross-QML/C++ compatibility. Returns a
`QVariantList` of `LayoutSlot` gadgets.

#### LayoutSlot Gadget

```cpp
struct LayoutSlot {
    QRectF rect;    // Position and size within the face
    int zOrder;     // Depth ordering
    qreal scale;    // Scale factor applied to the window
};
```

Exposed to QML as a value type via `QML_VALUE_TYPE(layoutSlot)` +
`QML_STRUCTURED_VALUE`.

#### Layout Modes

| Mode     | Enum value | Behavior                                                   |
|----------|------------|------------------------------------------------------------|
| Masonry  | 0          | Pack into columns, shortest-column-first. Aspect-preserving scale to fit column width. |
| Grid     | 1          | Equal-cell grid (auto rows x cols from sqrt). Windows centered in cells. |
| Stack    | 2          | All windows centered, `activeIndex` on top (zOrder = n). 90% face fill. |
| Freeform | 3          | Windows placed at center, no scaling. Position is initial only. |
| Cover    | 4          | Active window fills face. All others hidden (rect = 0, scale = 0). |

The layout mode enum is:

```cpp
namespace WorkSurfaceLayout {
    enum Mode { Masonry, Grid, Stack, Freeform, Cover };
}
```

---

## 4. QML Components

### 4a. Radial Menu Submenu System

**Files:** `RadialMenu.qml`, `RadialMenuNode.qml`

The radial menu was refactored from a flat 5-button design to support nested
submenus via a menu stack.

#### Menu Item Format

```javascript
menuItems: [
    { label: "Park Ray",  action: "parkRay" },
    { label: "Follow",    action: "follow",  enabled: someToggleState },
    { label: "Surface",   submenu: [
        { label: "Plane",    action: "addPlane" },
        { label: "Cube",     action: "addCube" },
        // ...
    ]}
]
```

Each item is a JS object with:
- `label`: Display text
- `action`: String identifier fired via `actionTriggered(string action)` signal
- `enabled`: Optional boolean, shows toggle state (red border when true)
- `submenu`: Optional array of child items. When present, clicking navigates into the submenu instead of firing an action.

#### Menu Stack

```javascript
property var menuStack: []  // Stack of {items, parentLabel}
readonly property var currentItems: menuStack.length > 0
    ? menuStack[menuStack.length - 1].items
    : menuItems
```

- `pushSubmenu(items, parentLabel)`: Pushes a new level onto the stack.
- `popSubmenu()`: Pops back to the parent level.
- Center button shows `"<"` when in a submenu (back navigation) and acts as
  close button at root level.
- `menuStack` is reset to `[]` on close animation completion.

#### Signal Chain

```
RadialMenu.onActionTriggered(action)
    -> RadialMenuNode.onActionTriggered(action)  [alias passthrough]
        -> XrScene radialMenuLoader delegate onActionTriggered handler
```

The `RadialMenuNode` wraps `RadialMenu` inside a `VRWindow` (2D-in-3D rendering
via texture compositing) and aliases all signals through.

#### Legacy Compatibility

The old `buttonClicked(int index)` and `buttonLabels`/`buttonEnabled` list
properties are preserved. The repeater model falls back to `buttonLabels.length`
when `currentCount` is 0.

### 4b. XrScene Delegate Structure (Inline Node)

**File:** `XrScene.qml`, lines 667-706

The work surface Repeater3D uses an inline delegate rather than an external component:

```qml
Repeater3D {
    id: workSurfaceRepeater
    model: WorkSurfaceModel { id: workSurfaceModel }
    delegate: Node {
        id: workSurface
        required property int index
        required property string surfaceId
        required property int shapeType

        property size itemSize: Qt.size(60, 40)
        property Node grabHandle: workSurface
        property bool _initialized: false

        Loader3D {
            id: wsShapeLoader
            sourceComponent: {
                switch (workSurface.shapeType) {
                case 0: return wsPlane
                case 1: return wsCube
                case 2: return wsCylinder
                case 3: return wsPyramid
                case 4: return wsSphere
                default: return wsPlane
                }
            }
        }

        Component.onCompleted: {
            // SpaceAllocator places it, then persist initial transform
            const globalPos = spaceAllocator.findFreePosition(...)
            workSurface.position = ...
            KwinVrHelpers.turnToFaceKeepRoll(workSurface, spaceAllocator.viewpoint)
            workSurfaceModel.updateTransform(surfaceId, ...)
            spaceAllocator.registerObject(workSurface)
            followMode.registerObject(workSurface)
        }
    }
}
```

Key points:
- `required property` declarations match model role names exactly.
- `_initialized` flag guards against premature transform persistence.
- The delegate is a child of `allWindowsGrabHandle`, same as output mirrors
  and application windows. This means it participates in the follow mode and
  grab-all operations.

### 4c. Shape Components

**File:** `XrScene.qml`, lines 710-815

Five shape components are defined as `Component` blocks inside `allWindowsGrabHandle`,
shared by all delegate instances via `Loader3D.sourceComponent`.

All shapes use a shared `wsFaceRect` component for their pickable faces:

```qml
Component {
    id: wsFaceRect
    Model {
        property real faceW: 60
        property real faceH: 40
        property Node grabHandle: null
        source: "#Rectangle"
        pickable: true
        scale: Qt.vector3d(faceW / 100, faceH / 100, 0.001)
        materials: PrincipledMaterial {
            baseColorMap: Texture {
                sourceItem: Rectangle {
                    // Wireframe appearance: translucent cyan fill,
                    // corner markers, center crosshair
                }
            }
            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            depthDrawMode: Material.OpaqueOnlyDepthDraw
        }
        depthBias: 50
    }
}
```

#### wsPlane
- 1 face, forward-facing, 60x40 world units.

#### wsCube
- 6 faces arranged as a box.
- Front/back at z=+/-30, left/right at x=+/-30, top/bottom at y=+/-20.
- Side faces are 60x40. Top/bottom faces are 60x60.

#### wsCylinder
- A visual `#Cylinder` Model (translucent white) for shape reference.
- 1 body face (188x40 -- unrolled circumference) facing forward.
- 2 cap faces (60x60) at y=+/-20, rotated to face up/down.

#### wsPyramid
- 4 slanted faces at calculated angles.
- Slant angle: `atan2(40, 30)` degrees from vertical.
- Slanted face size: 42x24. Base face: 60x60.

#### wsSphere
- A visual `#Sphere` Model (translucent white, scaled to r=30).
- 6 patch faces (36x36 each) positioned at +/-30 on each axis.
- Cube-sphere projection layout (one face per axis direction).

### 4d. WorkSurface3D.qml -- Standalone Component (Not Currently Used as Delegate)

**File:** `WorkSurface3D.qml`

A self-contained work surface component that includes:
- Its own `wireframeFace` Component (equivalent to `wsFaceRect` in XrScene)
- Shape components (`planeComponent`, `cubeComponent`, `cylinderComponent`,
  `pyramidComponent`, `sphereComponent`)
- Transform persistence via `onPositionChanged`/`onRotationChanged`/`onScaleChanged`
- Properties: `surfaceId`, `shapeType`, `ppu`, `selected`, `baseFaceWidth`,
  `baseFaceHeight`, `surfaceModel`, `_initialized`

This file is registered in CMakeLists.txt and compiles into the QML module.
It is NOT used as the Repeater3D delegate due to the `required property`
shadowing issue (see Section 7). It serves as:
1. Reference implementation for what a complete work surface component looks like
2. Potential future delegate if the property injection issue is resolved
3. Usable independently if surfaces are ever created outside of a Repeater3D

### 4e. WorkSurfaceFace.qml -- Designed But Not Yet Integrated

**File:** `WorkSurfaceFace.qml`

A per-face window container modeled after `KwinPseudoOutputMirror`. Features:

- **Pickable face surface** with wireframe material that changes color when
  windows are attached (cyan -> green).
- **ZStacker** for window depth ordering (uses `stackingOrder` property).
- **Window management API:**
  - `attachWindow(appWin)`: Adds to `attachedWindows`, sets `appWin.attachedFace`,
    calls `relayout()`.
  - `detachWindow(appWin)`: Removes from list, clears `attachedFace`, adjusts
    `activeIndex`, calls `relayout()`.
  - `relayout()`: Collects window sizes, calls
    `layoutEngine.computeLayout(layoutMode, faceSize, windowSizes, activeIndex)`,
    then positions each window.
  - `cycleActiveIndex(delta)`: For Stack/Cover modes, cycles through windows.
- **UV coordinate conversion:** `uvToLocalPosition(coords)` maps ray pick UV
  (0-1) to local 3D coordinates on the face.

**Integration status:** This component exists and compiles but is not yet wired
into the shape components. The current shapes use the simpler `wsFaceRect`
component (pickable rectangles without window hosting logic). Integrating
`WorkSurfaceFace` requires replacing `wsFaceRect` loaders inside each shape
component with `WorkSurfaceFace` instances.

### 4f. TransformGizmo3D.qml -- Designed But Not Yet Integrated

**File:** `TransformGizmo3D.qml`

A 3D manipulation widget with:

- **Translation arrows:** Cylinder + cone along each axis (X=red, Y=green, Z=blue).
  All parts are pickable with a `handleId` property.
- **Rotation rings:** Flattened sphere approximations for each rotation plane.
  Semi-transparent (0.4 opacity).
- **Scale handles:** Small cubes at axis endpoints + center cube for uniform scale.
- **Action buttons:** Delete (red circle with "X") and Duplicate (blue circle
  with "+"), implemented as `VRWindow` items (2D-in-3D).
- **Interaction API:**
  - `beginDrag(handleId, rayPos)`: Saves initial state.
  - `updateDrag(rayPos)`: Applies delta to target node's position or scale.
  - `endDrag()`: Clears active handle.
  - `isGizmoHandle(obj)`: Checks if a picked object is a gizmo part.

**Integration status:** The gizmo component exists and compiles, but:
- It is not instantiated in XrScene when a surface is selected.
- The `VrFocusControl`/`VrPicking` system does not yet route picks on gizmo
  handles to the gizmo's drag methods.
- Rotation dragging is noted as "more complex" and is not yet implemented
  (the `updateDrag` method has a comment placeholder for it).

### 4g. VrWindowManipulation Extensions

**File:** `VrWindowManipulation.qml`

Extended with work surface integration:

#### rayPickWorkSurfaceFace()

Walks the ray pick results and traverses parent chains looking for a
`WorkSurfaceFace` instance. Returns `{ face, pick }` or `null`.

```javascript
function rayPickWorkSurfaceFace(): var {
    const allPicks = root.picking.lastAllPicks
    for (var pickResult of allPicks) {
        let node = pickResult.objectHit ?? root.picking.getHoveredNodeFromItem(pickResult.itemHit)
        while (node) {
            if (node instanceof WorkSurfaceFace) {
                return { face: node, pick: pickResult }
            }
            node = node.parent
        }
    }
    return null
}
```

#### detachWindowFromSurface(appWin)

Calls `face.detachWindow(appWin)` when a window attached to a surface face is
grabbed for moving.

#### lookForScreenToPut Connection (Extended)

After checking for pseudo output hits, the connection now also checks for work
surface face hits:

```javascript
const surfaceHit = root.rayPickWorkSurfaceFace()
if (surfaceHit) {
    surfaceHit.face.attachWindow(appWin)
    xray.release()
    return  // Window stays vr=true, just reparented to face
}
```

#### movingResizingWindowWatcher (Extended)

When a VR window starts moving, if it has an `attachedFace`, it is first
detached from the surface before being grabbed by the ray.

### 4h. KwinApplicationWindow "surface" State

**File:** `XrScene.qml`, lines 610-622

A third state was added to the application window delegate's state machine:

```qml
State {
    name: "surface"
    when: kwinAppWindow.client.vr && kwinAppWindow.attachedFace !== null
    PropertyChanges {
        kwinAppWindow {
            parent: kwinAppWindow.attachedFace
            grabHandle: kwinAppWindow
            rotation: Qt.quaternion(1, 0, 0, 0)
            zOffsetGlobal: 0
        }
    }
    StateChangeScript {
        script: followMode.unregisterObject(kwinAppWindow)
    }
}
```

The `surface` state takes priority over `vr` because both share `client.vr === true`
but the `surface` state additionally requires `attachedFace !== null`. This is
ordered first in the `states` array.

---

## 5. Current Status -- What Works

### Radial Menu

- [x] Submenu system with `menuItems` + `menuStack` navigation
- [x] "Surface" button in root menu opens shape submenu
- [x] Back button (center, shows "<") returns to root menu
- [x] `actionTriggered(string action)` signal chain from RadialMenu through
      RadialMenuNode to XrScene handler
- [x] Dynamic button count and angular spacing per menu level
- [x] All 5 shape actions dispatch to `xrView.addWorkSurface()`

### Model CRUD + Persistence

- [x] `addSurface()` creates entries with correct face counts
- [x] `removeSurface()` and `duplicateSurface()` implemented
- [x] `updateTransform()` persists position/rotation/scale changes
- [x] `setFaceLayoutMode()` updates per-face layout config
- [x] JSON save/load with 500ms debounce
- [x] Face count auto-correction on load (pads or trims to expected count)

### Scene Integration

- [x] `Repeater3D` with inline `Node` delegate driven by `WorkSurfaceModel`
- [x] `SpaceAllocator3D` placement of new surfaces at free positions
- [x] `turnToFaceKeepRoll` orients surfaces toward the camera on creation
- [x] Registration with `spaceAllocator` and `followMode`
- [x] Follow mode and grab-all inclusion (surfaces move with `allWindowsGrabHandle`)

### Shape Rendering

- [x] All 5 shape components (`wsPlane`, `wsCube`, `wsCylinder`, `wsPyramid`, `wsSphere`)
      defined with appropriate geometry
- [x] Wireframe face rendering with translucent cyan fill, corner markers, and
      center crosshair
- [x] Cylinder and sphere include translucent visual reference meshes
- [x] `Loader3D` switch selects the correct shape component by `shapeType` enum

### Build System

- [x] `worksurfacemodel.h/.cpp` and `worksurfacelayout.h/.cpp` in `SOURCES`
- [x] `WorkSurface3D.qml`, `WorkSurfaceFace.qml`, `TransformGizmo3D.qml` in `QML_FILES`

---

## 6. Open Questions / Testing Needed

### Are all 5 shapes rendering correctly with proper geometry?

**Unknown.** The shape components are defined but have not been verified visually
in a running VR session. Specific concerns:

- Pyramid slant angles -- the trigonometry (`atan2(40, 30)`) may produce faces
  that don't meet at the apex cleanly. The face positions
  (`Qt.vector3d(0, 10, 15)` etc.) are approximations.
- Cylinder body face -- it's a flat 188-unit-wide rectangle facing forward.
  It does NOT wrap around the cylinder. This is a flat approximation of the
  unrolled surface. For actual curved face hosting, integration with
  `CurvedPlaneGeometry` (which exists in the codebase) would be needed.
- Sphere patches -- the 6 flat faces at 30-unit offsets will have visible gaps
  where the sphere surface curves away from them. The `fs = r * 1.2` sizing
  provides some overlap.

### Does window snapping to surfaces work?

**Partially wired, not functional end-to-end.** The code path is:

1. VrWindowManipulation.lookForScreenToPut calls `rayPickWorkSurfaceFace()` -- **exists**
2. `rayPickWorkSurfaceFace()` walks picks looking for `WorkSurfaceFace` instances -- **exists**
3. But the current shapes use `wsFaceRect` (a plain `Model`), NOT `WorkSurfaceFace` -- **gap**

The `instanceof WorkSurfaceFace` check will never match because no
`WorkSurfaceFace` instances exist in the scene. The window snapping pipeline is
complete in code but disconnected at the component level.

### Does the transform gizmo work?

**No.** TransformGizmo3D.qml is defined but never instantiated. There is:
- No selection mechanism that shows the gizmo when a surface is clicked
- No wiring from the ray pick system to the gizmo's `beginDrag`/`updateDrag`/`endDrag`
- Rotation drag is not implemented (only translation and scale)

### WorkSurfaceFace integration status

**Not integrated.** WorkSurfaceFace.qml exists as a complete component with:
- Window attach/detach
- Layout engine calls
- ZStacker
- UV coordinate mapping
- Color change when windows are present

But it is not used by any shape component. The shapes use the simpler `wsFaceRect`
component instead.

### Layout engine integration status

**C++ complete, QML disconnected.** The layout engine:
- Compiles and is registered as a QML singleton
- Implements all 5 layout algorithms
- Returns properly structured `LayoutSlot` gadgets

But `WorkSurfaceFace.relayout()` (which calls the engine) is never executed
because `WorkSurfaceFace` is not instantiated in the scene.

### Persistence across VR sessions

**Partially working.** The model loads saved surfaces on construction and the
Repeater3D will recreate delegates. However:
- Saved transforms (position/rotation/scale) are loaded into the model but the
  delegate's `Component.onCompleted` always calls `spaceAllocator.findFreePosition()`
  for placement, ignoring the persisted position. The loaded position roles
  (`surfacePosition`, `surfaceRotation`, `surfaceScale`) are available on the
  model but not bound to the delegate's Node position.
- The delegate immediately overwrites the persisted transform with the allocator's
  position via `updateTransform()`.

**This means persistence saves correctly but restores are overwritten on load.**

### Missing Pieces for Full Feature

1. **WorkSurfaceFace integration** into shape components (replace `wsFaceRect` with
   `WorkSurfaceFace`)
2. **Transform gizmo** instantiation and interaction wiring
3. **Position restore** from persisted data (skip allocator for loaded surfaces)
4. **Selection system** (clicking a surface selects it, shows gizmo)
5. **Rotation gizmo drag** implementation
6. **Curved face geometry** for cylinder body (use `CurvedPlaneGeometry`)

---

## 7. Known Issues & Lessons Learned

### The Required Property Shadowing Bug

**Problem:** When using an external QML component as a `Repeater3D` delegate,
if that component declares properties with the same names as model roles,
the component's own property declarations shadow the model-injected values.
The delegate receives default/empty values instead of the model data.

**Example of the bug:**

```qml
// WorkSurface3D.qml
Node {
    property string surfaceId: ""    // <-- This shadows the model's surfaceId role
    property int shapeType: 0        // <-- This shadows the model's shapeType role
}

// XrScene.qml
Repeater3D {
    model: WorkSurfaceModel {}
    delegate: WorkSurface3D {}       // surfaceId and shapeType stay at defaults!
}
```

**Root cause:** Qt Quick's `required property` injection from a model into a
delegate only works correctly when the properties are declared with `required`
in the delegate's root scope. If the component also has non-required properties
with the same names, the component's own default values take precedence.

**Solution:** Use an inline delegate in XrScene.qml with `required property`
declarations:

```qml
delegate: Node {
    required property int index
    required property string surfaceId
    required property int shapeType
    // These ARE properly injected by the model
}
```

### Journald Rate Limiting Hiding QML console.log

**Problem:** During rapid model operations (adding surfaces, multiple
`dataChanged` emissions), `console.log` and `qCDebug` output was silently
dropped. Logs appeared to stop, making it look like code wasn't executing.

**Root cause:** systemd-journald has a default rate limit
(`RateLimitIntervalSec=30s, RateLimitBurst=10000`). When KWin-VR produces
burst logging during model operations, journald drops messages without warning.

**Solution:** The model uses a file-based logger (`wsLog()`) that writes directly
to `/tmp/kwinvr-worksurface.log`:

```cpp
static void wsLog(const QString &msg) {
    QFile f(QStringLiteral("/tmp/kwinvr-worksurface.log"));
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        f.write(QDateTime::currentDateTime().toString(Qt::ISODateWithMs).toUtf8());
        f.write(" ");
        f.write(msg.toUtf8());
        f.write("\n");
    }
}
```

This should be removed or gated behind a debug flag before merging to main.

### Position Persistence Timing (Component.onCompleted Ordering)

**Problem:** The delegate's `Component.onCompleted` handler runs after the
delegate is created but before the model's persisted position data can be
applied. The handler calls `spaceAllocator.findFreePosition()` unconditionally,
which overwrites any previously saved position.

**Solution needed:** Check whether the model has a non-zero saved position for
this surface. If so, restore it instead of asking the allocator for a new one.
Something like:

```qml
Component.onCompleted: {
    // Check if model has a saved position
    const savedPos = workSurfaceModel.data(
        workSurfaceModel.index(index, 0),
        WorkSurfaceModel.PositionRole
    )
    if (savedPos && savedPos.length() > 0.01) {
        workSurface.position = workSurfaceRepeater.mapPositionFromScene(savedPos)
        // Restore saved rotation/scale too
    } else {
        // New surface: use allocator
        const globalPos = spaceAllocator.findFreePosition(...)
        workSurface.position = workSurfaceRepeater.mapPositionFromScene(globalPos)
        KwinVrHelpers.turnToFaceKeepRoll(workSurface, spaceAllocator.viewpoint)
    }
    workSurface._initialized = true
    spaceAllocator.registerObject(workSurface)
    followMode.registerObject(workSurface)
}
```

---

## 8. Next Steps

### Priority 1: Make Window Snapping Work

This is the core value proposition. Without window snapping, surfaces are
decorative geometry.

1. **Replace `wsFaceRect` with `WorkSurfaceFace`** in the shape components
   (or at least in `wsPlane` as a first test). Each `Loader3D` for a face
   needs to load a `WorkSurfaceFace` instance instead of a `wsFaceRect` Model.
2. **Pass required properties** to `WorkSurfaceFace`: `faceWidth`, `faceHeight`,
   `ppu`, `layoutMode`, and a reference to the `WorkSurfaceLayoutEngine` singleton.
3. **Test the snap pipeline:** Grab a VR window, drag it toward a face, verify
   that `rayPickWorkSurfaceFace()` detects the face, and the window reparents
   and layouts.

### Priority 2: Fix Position Persistence

1. **Add restore logic** to the delegate's `Component.onCompleted` as described
   in Section 7.
2. **Test round-trip:** Add a surface, move it, restart VR, verify it appears at
   the saved position.

### Priority 3: Selection + Transform Gizmo

1. **Add selection detection** in `VrFocusControl` or `VrPicking`: clicking on a
   work surface face (non-window area) should call `xrView.selectWorkSurface()`.
2. **Instantiate TransformGizmo3D** as a child of the selected surface, bind
   `targetNode` to the surface Node.
3. **Wire gizmo interaction** through the pick system: detect picks on gizmo
   handles, call `beginDrag`/`updateDrag`/`endDrag`.
4. **Implement rotation dragging** in the gizmo (currently only translation and
   scale are implemented).

### Priority 4: Layout Mode Switching

1. **Add UI** to switch layout modes per face (context menu on right-click, or a
   button on the face, or a gizmo widget).
2. **Call `workSurfaceModel.setFaceLayoutMode()`** when the user switches.
3. **Test each layout mode** with multiple windows on a single face.

### Priority 5: Polish

- Remove `wsLog()` debug logging or gate behind a build flag
- Handle edge cases: window resize while attached, surface deletion with
  attached windows
- Add visual feedback for hover/drop targets when dragging a window near a face
- Consider curved face geometry for cylinder body using `CurvedPlaneGeometry`
- Test all shapes thoroughly for visual correctness
- Clean up the unused legacy `buttonClicked(int index)` path in the radial menu

---

## Appendix: File Reference

| File | Role |
|------|------|
| `src/plugins/vr/worksurfacemodel.h` | C++ model header -- enums, data structs, model class |
| `src/plugins/vr/worksurfacemodel.cpp` | C++ model impl -- CRUD, persistence, JSON serialization |
| `src/plugins/vr/worksurfacelayout.h` | C++ layout engine header -- LayoutSlot, engine class |
| `src/plugins/vr/worksurfacelayout.cpp` | C++ layout engine impl -- 5 layout algorithms |
| `src/plugins/vr/qml/XrScene.qml` | Main scene -- delegate, shape components, menu handler |
| `src/plugins/vr/qml/WorkSurface3D.qml` | Standalone surface component (not used as delegate) |
| `src/plugins/vr/qml/WorkSurfaceFace.qml` | Face component with window hosting (not yet integrated) |
| `src/plugins/vr/qml/TransformGizmo3D.qml` | 3D gizmo component (not yet integrated) |
| `src/plugins/vr/qml/RadialMenu.qml` | Radial menu with submenu stack |
| `src/plugins/vr/qml/RadialMenuNode.qml` | 3D wrapper for RadialMenu |
| `src/plugins/vr/qml/VrWindowManipulation.qml` | Window move/snap/detach logic |
| `src/plugins/vr/CMakeLists.txt` | Build system -- all files registered |
| `~/.config/kwinvr-worksurfaces.json` | Persistence file (runtime) |
| `/tmp/kwinvr-worksurface.log` | Debug log (runtime, temporary) |
