# Work Surfaces Overhaul Plan

**Branch:** `feature/work_surfaces`
**Drafted:** 2026-04-16
**Supersedes the wsFaceRect / frame-style-face target model described in `WORK_SURFACES.md` sections 4c/4e.**

---

## Goal

Replace the translucent cyan "face rectangle" target model with:

- **True geometry wireframes** per primitive, shown only while any window is being dragged anywhere in the scene, OR when the surface hosts zero windows (so empty surfaces stay discoverable).
- **UV-projected windows** deformed onto the primitive's actual surface shape when snapped. Deformation is permanent for snapped windows (always visible, no wireframe dependency).
- **Drag preview** that reuses the normal grab-snap proximity behavior: when a grabbed window's ray lands on a primitive region, the window renders as a deformed ghost projection on that region; on release → commit snap; drag off → revert to flat VR window.
- **Windows never scale.** Scale the primitive to change effective UV coverage. Overflow → permit scale-down-to-fit as a forced exception only.
- **Edit surface** via `editSurface` action in the hosted-window's radial submenu; reuses existing `TransformGizmo3D`.
- **Layout mode** picker as a sub-radial on the surface's radial menu.

---

## Answered Spec (reference)

| # | Question | Answer |
|---|----------|--------|
| 1 | Window scales with primitive? | **No, never.** Primitive scales; window UV coverage changes accordingly. |
| 2 | Region topology | Use regions (current face counts from `WORK_SURFACES.md` §3a). |
| 3 | Cylinder body wrap | Full height, wrap arc derived from window width at current primitive radius. |
| 3 | Sphere | One region to start. Iterate later. |
| 4 | Geometry | Write new geometry classes per primitive where curvature needed. |
| 5 | Snapped window render | Always deformed to primitive shape, regardless of wireframe visibility. |
| 6 | Layout engine | Keep. Stack on sphere = onion layers, radial offset = pseudomirror stack scale. |
| 7 | Snap commit | On grab release. |
| A1 | Translucent ref meshes | Kill entirely. |
| A2 | Overflow | Allow forced scale-down to fit. |
| A3 | Pyramid regions | 5 (4 slanted + base). |
| A4 | Back-side faces | Only visible-side snappable. User rotates primitive to use others. |
| A5 | Sphere regions | 1 to start. |
| A6 | Stack onion offset | Same scale as pseudomirror Z-stack. |
| A7 | Gizmo trigger | Hosted-window radial → `editSurface`. Empty surfaces: always wireframe. |
| A8 | Wireframe style | Geometry edges only, no region outlines. |

---

## Phases

Each phase self-contained and independently testable. Phase boundaries also mark safe stopping points — the branch should build + render at each phase end.

### Phase A — Wireframe primitives, kill facerect & ref meshes

**Goal:** Visually replace current geometry with true edge wireframes. Visibility rules wired. No functional change to snap/layout.

**Files:**
- `src/plugins/vr/qml/XrScene.qml` (lines 710-815: `wsPlane`/`wsCube`/`wsCylinder`/`wsPyramid`/`wsSphere` Components + `wsFaceRect` Component)
- Optionally new `src/plugins/vr/qml/WsWireframe.qml` for shared edge-drawing helpers

**Steps:**
1. Delete `wsFaceRect` Component entirely.
2. Delete `#Cylinder` and `#Sphere` translucent ref meshes from `wsCylinder` / `wsSphere`.
3. Replace each shape Component with an edge-wireframe Node:
   - `wsPlane`: 4 edge lines (rectangle outline at face size).
   - `wsCube`: 12 edges.
   - `wsCylinder`: top + bottom circle (N segments, ~32), plus a small number of vertical spines (e.g. 8) for visual readability.
   - `wsPyramid`: 4 apex-to-base + 4 base = 8 edges.
   - `wsSphere`: lat/lon wireframe (e.g. 8 longitudes, 5 latitudes).
4. Implement edges as thin `#Cylinder` primitives between endpoints, or as a new `QQuick3DGeometry` subclass `EdgeLineGeometry` that builds line-topology VBOs. Start with `#Cylinder` approach (zero C++ required); upgrade later if perf/look requires.
5. Visibility predicate on each shape Node:
   - `visible: workSurface.hostedWindowCount === 0 || xrView.anyWindowDragging`
   - Add `hostedWindowCount` property on the delegate Node (updated via attach/detach later; initially always 0).
   - Add `xrView.anyWindowDragging` boolean — driven by `VrWindowManipulation` grab state. If a single flag doesn't cleanly exist, add one.
6. Material: unlit, single color, slight additive blend. No texture.

**Test criteria:**
- All 5 primitives render as wireframes at creation.
- Wireframe disappears when no drag active AND hostedWindowCount > 0 (force via temporary debug toggle until Phase D).
- Wireframe reappears during any VR window drag.
- Scene no longer contains cyan fill quads or white translucent spheres/cylinders.

**Blockers:** None.

---

### Phase B — Curved region geometries

**Goal:** C++ geometry classes for the curved regions. Flat regions (plane face, cube face, pyramid face) do not need new geometry — a tilted `#Rectangle` is sufficient. This phase is pure backend: no scene changes yet.

**Files (new):**
- `src/plugins/vr/cylinderbodygeometry.{h,cpp}` — full-height wrap, arc angle derived from (window width at surface radius).
- `src/plugins/vr/spherepatchgeometry.{h,cpp}` — spherical cap / lat-lon patch.
- `src/plugins/vr/CMakeLists.txt` — register both.

**Design:**
- Reuse `CurvedPlaneGeometry` (src/plugins/vr/curvedplanegeometry.h) as a reference. It already does horizontal curvature — for **cylinder body** we can likely reuse it directly by computing `curvature = arcAngle` from window width / radius. Decision point during phase: subclass or parameter extension. Prefer reuse.
- `SpherePatchGeometry`: inputs `(centerLatLon, widthAngular, heightAngular, radius, segs)`; outputs UV-mapped curved patch. Vertex = `r * (cos φ cos θ, sin φ, cos φ sin θ)` with UVs linear in (θ, φ).
- All geometries expose a `textureMaterial`-ready UV layout so the existing `WindowTextureMaterial` works unmodified.

**Test criteria:**
- Build passes. Manual smoke test: drop a `Model { geometry: CylinderBodyGeometry { ... } }` in a test QML, confirm shape.
- Not yet integrated into work surfaces.

**Blockers:** None.

---

### Phase C — Region descriptor refactor

**Goal:** Replace implicit face topology (hardcoded `wsFaceRect` placements in each shape Component) with explicit region descriptors the model and QML both understand. Needed so Phase E's snap pipeline and Phase D's deformation know *where each region is* in local surface space.

**Files:**
- `src/plugins/vr/worksurfacemodel.{h,cpp}` — extend `WorkSurfaceFaceData` with region geometry: kind (flat/cylinder-body/sphere-patch), origin, basis vectors, extent, curve params.
- `src/plugins/vr/qml/XrScene.qml` — shape Components stop positioning windows via nested `Loader3D`s; instead expose region descriptors matching the model.

**RegionKind enum:** `FlatRect`, `CylinderBody`, `SpherePatch`.

**Per shape (visible-side only):**

| Shape    | Regions | Kinds |
|----------|---------|-------|
| Plane    | 1 | FlatRect |
| Cube     | 3 visible (front, top, one side — TBD by camera angle OR always front+top+right) | FlatRect × 3 |
| Cylinder | 2 (body + top cap) | CylinderBody + FlatRect |
| Pyramid  | 3 (front slant + two visible slants; base hidden from above) — **OR** all 5, filter visibility at snap time | FlatRect × N |
| Sphere   | 1 | SpherePatch |

**Decision for cube/pyramid visible-region set:** deferred to Phase E. Simplest path: expose all regions in the model, filter for "camera-facing" at snap time. Keeps persistence stable if user rotates primitive.

**Test criteria:**
- `addSurface` still creates correct region counts per shape.
- Persistence round-trips region descriptors.
- No visual regression (Phase A wireframes still render).

**Blockers:** None.

---

### Phase D — Window deformation on snap

**Goal:** A snapped window renders as a curved/tilted mesh matching its region, sampling the existing window texture. Window world size is preserved; primitive scale determines UV coverage fraction.

**Files:**
- `src/plugins/vr/qml/KwinApplicationWindow.qml` (or wherever the `surface` state is defined, per `WORK_SURFACES.md` §4h lines 610-622 of `XrScene.qml`).
- New `src/plugins/vr/qml/WsDeformedWindow.qml` — Model-with-region-geometry that reads window texture.

**State transition:**
- Current `surface` state reparents to `attachedFace`.
- New: when in `surface` state, swap the flat window `Model` for a `WsDeformedWindow` instance parameterized by the face's region descriptor + the window's native size.
- UV coverage:
  - `FlatRect`: window positioned & rotated onto the flat face at its native world size.
  - `CylinderBody`: arc = `windowWidth / primitiveRadius` (radians), full height = windowHeight; overflow if arc > 2π → force scale-down.
  - `SpherePatch`: angular extent = `windowSize / (primitiveRadius * scale)`; overflow if > patch bounds → force scale-down.
- Explicitly do **not** apply primitive scale to the window mesh. Window keeps its own world size; position/orientation on primitive uses primitive scale only for origin math.

**Stack onion (sphere):**
- For `Stack` layout mode, slot `zOrder` offsets window radially outward by `zOrder * pseudoMirrorStackOffset`. Look up that constant from `KwinPseudoOutputMirror.qml` (or wherever the pseudo-output Z stacking spacing lives) and reuse verbatim.

**Test criteria:**
- Attach a window to a plane → renders flat, correct world size.
- Attach to cube front face → renders flat, tilted to face normal.
- Attach to cylinder body → renders as curved arc, visible from outside the cylinder.
- Attach to sphere → renders as curved patch.
- Scale primitive 2× → window stays same world size; region has room for more windows.
- Wireframe hides when snapped (hostedWindowCount > 0, no drag) — snapped window still visible.

**Blockers:** Phase C (region descriptors).

---

### Phase E — Drag preview + commit pipeline

**Goal:** During a VR window grab, if the ray approaches a primitive region, show a ghost-deformed preview of the window on that region. On release → commit (normal state transition to `surface`). On drag off → ghost disappears, window is a normal VR window again.

**Files:**
- `src/plugins/vr/qml/VrWindowManipulation.qml` (§4g of `WORK_SURFACES.md`: `rayPickWorkSurfaceFace`, `lookForScreenToPut` extension).
- `src/plugins/vr/qml/XrScene.qml` delegate.

**Steps:**
1. Rework `rayPickWorkSurfaceFace` to pick against wireframe edges + invisible face hit-proxies (simple flat pickable quads per region, transparent) since `wsFaceRect` is gone. Hit proxies do not render — they only participate in picking. Register them with region descriptors so the pick result carries `{surfaceId, regionIndex, uv, localPos}`.
2. Extend `lookForScreenToPut`:
   - On pick hit of a work-surface region while grab active → spawn/update preview: a `WsDeformedWindow` instance parented to the region, textured from the grabbed window's texture, positioned by region's layout engine result for an active preview slot.
   - On pick miss or ray moves away → destroy preview.
3. On grab release with preview active → normal snap commit (existing `attachWindow` path).
4. On grab release without preview → window stays free.
5. `xrView.anyWindowDragging` flag (introduced Phase A) toggled by grab start/end so wireframes appear scene-wide during any drag.

**Test criteria:**
- Drag window near plane → see curved/flat preview on plane.
- Drag window near cylinder body → see curved preview wrapping arc.
- Release on primitive → window snaps, preview becomes real.
- Release off primitive → window stays where released, no snap.
- Drag another window while one is already snapped → wireframes on all primitives visible during drag.

**Blockers:** Phase D (deformed window component).

---

### Phase F — Layout engine fit to curved regions

**Goal:** Multi-window per region using existing `WorkSurfaceLayoutEngine` (Masonry/Grid/Stack/Freeform/Cover). Tune onion stack on sphere.

**Files:**
- `src/plugins/vr/worksurfacelayout.cpp` (possibly tweaks).
- `src/plugins/vr/qml/WorkSurfaceFace.qml` (§4e of `WORK_SURFACES.md`) — now integrated via Phase C's region descriptors.

**Steps:**
1. Layout engine's `faceSize` input: for `FlatRect`, use flat dimensions. For `CylinderBody`, use (circumference-arc-length, height) at current radius — the engine sees a flat unroll. For `SpherePatch`, use (patchArcWidth × radius, patchArcHeight × radius) similarly.
2. Per-slot mapping: engine returns a `QRectF` in unrolled coords; Phase D's deformation converts that rect into curved geometry UVs.
3. Stack layout `zOrder`: Phase D's radial offset logic consumes this.
4. No code change expected to engine itself — purely hook-up.

**Test criteria:**
- Three windows on plane, Masonry: shortest-column packing behaves correctly.
- Three windows on cylinder, Stack: stacked along arc center, zOrder → radial outward steps.
- Three windows on sphere, Stack: onion layering visible.
- Cover: active fills region, others hidden.

**Blockers:** Phase D.

---

### Phase G — Edit surface via hosted-window radial + empty-surface wireframe

**Goal:** User invokes the hosted-window's radial menu → `Edit Surface` item → selects the surface → shows `TransformGizmo3D` → commits transforms to model.

**Files:**
- `src/plugins/vr/qml/RadialMenu.qml` wiring site (wherever per-target menu items are assembled for a hovered/hosted window).
- `src/plugins/vr/qml/XrScene.qml` (radial menu handler around lines 703-755).
- `src/plugins/vr/qml/TransformGizmo3D.qml` — already exists; instantiate when `xrView.selectedSurfaceId` is non-empty.

**Steps:**
1. Detect when radial menu target is a window whose `attachedFace` resolves to a work surface; add `{ label: "Edit Surface", action: "editSurface" }` item.
2. `editSurface` action → sets `xrView.selectedNode` = the parent surface Node, `xrView.selectedSurfaceId` = its id.
3. Instantiate `TransformGizmo3D` as child of the selected surface Node, `targetNode: workSurface`.
4. Wire gizmo picks into `VrFocusControl` / `VrPicking` (handle id routing → `beginDrag`/`updateDrag`/`endDrag`).
5. Rotation drag: implement the placeholder in `TransformGizmo3D.updateDrag` (axis-locked quaternion delta from ray projection onto the ring plane).
6. Empty-surface wireframe rule already in Phase A; confirm `hostedWindowCount === 0` path still visible.
7. `Done` action (already exists) clears selection, hides gizmo.

**Test criteria:**
- Right-click a window on a surface → radial shows `Edit Surface`.
- Click it → gizmo appears around the parent primitive.
- Drag translation/rotation/scale → primitive + hosted windows move/rotate; window world sizes unchanged (scale independence from Phase D).
- `Done` hides gizmo.

**Blockers:** Phase D (so hosted windows move with primitive visibly).

---

### Phase H — Layout mode sub-radial on surface menu

**Goal:** Add a layout-mode picker accessible from the surface's own radial menu (not window's).

**Files:**
- `src/plugins/vr/qml/XrScene.qml` radial menu handler.
- `src/plugins/vr/worksurfacemodel.cpp` — `setFaceLayoutMode` already exists.

**Steps:**
1. When radial target is a work surface primitive itself, add submenu item `{ label: "Layout", submenu: [Masonry, Grid, Stack, Freeform, Cover] }`.
2. On selection → `workSurfaceModel.setFaceLayoutMode(surfaceId, regionIndex, modeEnum)`.
3. Per-region: if surface has multiple regions, the submenu needs to identify which region. Start with "active region = region under radial-menu-invoke point"; persist on all if ambiguous. Tune in testing.

**Test criteria:**
- Invoke radial on a primitive → `Layout` submenu appears.
- Pick each mode → windows re-layout on the region.
- Selection persists across restart.

**Blockers:** Phase F.

---

### Phase I — Cleanup + docs

**Goal:** Remove dead code, update docs, tidy logging.

**Steps:**
1. Remove `WorkSurfaceFace.qml`'s unused fallback path if Phase C fully absorbs it; else keep and document as active component.
2. Remove `WorkSurface3D.qml` if still unused (§4d). Confirm nothing references it.
3. Gate `wsLog()` behind a build flag or remove (§7 of `WORK_SURFACES.md`).
4. Update `WORK_SURFACES.md`: replace §4c/§4e/§6 gap list to reflect new reality. Link this file in history.
5. Remove legacy `onButtonClicked(index)` handler in radial menu if nothing still relies on it (§4a legacy compat note).

---

## Cross-cutting concerns

- **`anyWindowDragging` signal source.** Needed by Phase A. Likely lives in `VrWindowManipulation` or `VrPicking`. If no clean existing flag, add one driven by grab-start/grab-end in `VrWindowManipulation`.
- **Hit-proxy picking without visible faces.** Phase E requires transparent pickable quads per region. Confirm Qt Quick 3D allows `pickable: true; visible: false` — per `feedback_qt3d_xr_rendering.md` memory, `visible: false` is broken in 6.6.3 XR. Workaround: opacity 0 or material with alpha 0 and `pickable: true`. Verify during Phase E.
- **Position persistence** (§6 bullet 6 of `WORK_SURFACES.md`) — orthogonal to overhaul; fix separately or fold into Phase G.
- **Debug log file** `/tmp/kwinvr-worksurface.log` still active; harmless during overhaul, remove in Phase I.

---

## Ordering summary

A → B (parallel with A) → C → D → E → F → G → H → I

A is visually safe first step. B is pure backend. C is a refactor. D is where windows start projecting. E makes drag-and-drop work. F tunes multi-window layouts. G brings back gizmo editing. H adds layout switching. I is cleanup.
