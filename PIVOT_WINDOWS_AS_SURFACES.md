# Pivot: Windows as Surfaces — Spatial Grammar for a VR-Native Desktop

**Proposed branch:** `feat/windows_as_surfaces`
**Base:** `6.6.3_vr_bake` @ `95947c85b6` (post window-spawning fix)

This document captures the next refactor direction for KWin-VR. It is
written to survive a context dump — read top-to-bottom and you should
have enough to start the branch cold.

---

## 1. Philosophy

KWin-VR is not a "VR window manager." It is the compositor foundation for
a **VR-native desktop operating system** — the next paradigm after terminal
and 2D windowed. The thesis:

- **No gimmicks.** No floating plant on a virtual desk. No "subscribe for
  more monitors." No fake loft apartment. No hard cap of three windows.
- **Performance and utility first.** VR output overhead stays low, input
  stays snappy, the interface gets out of the way.
- **The virtual monitor is backplane, not stage.** Its only job is to give
  the system bounding geometry for things that need a rectangle — DPI,
  fullscreen, `fbconfig`. It is not the primary residence of windows.
- **Windows are floating-first.** Pinning a window to an output is an
  explicit user action (drop onto pseudo-mirror), not the default.
- **Unlimited spatial real estate.** No pixel budget, no bezels. A 3D
  desktop is not a bigger monitor; it is a workspace without monitors.
- **Hardware spectrum matters.** The target is everything from an Orange
  Pi 5B + ancient Xreal glasses + pocket keyboard up to a gaming rig,
  and includes weird cases (Arch-in-WSL bubbling a VR shell to Windows).
  Design choices must not assume a specific HMD or GPU class.

The first-order job of this project is **defining the UX grammar of 3D
productivity.** Other "VR desktops" borrow 2D constraints (one rectangle
per monitor, everything else is void or decoration). We're designing the
equivalent of snap/tile/minimize/maximize for three dimensions.

### What ubiquitous functions does a 3D productivity interface need?

From the 2D world we inherit: resize, move, close, minimize, maximize,
snap, tile, focus-on-click, alt-tab. Translating those to 3D is partial.
The 3D-native additions we are exploring:

- **Float and face.** Windows live in space, oriented toward the user by
  default; re-face on camera move.
- **Pin to space / pin to camera / pin to other window.** Three scopes of
  "stuck to" for different workflows (video-while-walking, anchored
  reference, grouped editing).
- **Stack.** Rolodex / booklet of windows in one spatial slot; titles
  visible; click to bring front or pluck out.
- **Lasso.** A right-click drag rectangle selects windows for group
  operations — the 3D analogue of desktop lasso select.
- **Gather / reflow.** Collect all floating windows into a sane layout in
  front of the user. The "recenter everything" button.
- **Radial menu with context.** Empty-space lasso opens group options
  (pin-together / stack / gather / close-all). Single-window targets get
  the same menu with single-window actions.

Work surfaces (curved UV-projection onto primitives) were an early attempt
to give windows structure in space. They added complexity (spherepatch,
cylinderbody geometries; UV math; surface-face snapping) and still left
the user managing a second primitive kind. **The windows themselves are
already the surfaces we need.** Pinning two windows together makes the
second one a face on the first.

---

## 2. Goals of this branch

1. **Gut** work-surface + curved-UV code end to end.
2. **Build** the lasso-to-group workflow: right-drag selects, radial menu
   acts on the selection.
3. **Implement** three group relations:
   - **Pin-to-space** (current float behavior, now the default)
   - **Pin-to-camera** (PIP-lite: window follows head)
   - **Pin-to-window** (child window anchored to parent; parent becomes a
     surface)
   - **Stack** (ordered offset stack; titlebars visible, click to front,
     drag out)
4. **Preserve** everything already working on `6.6.3_vr_bake`: auto-float
   on hidden output, focus pull + follow-mode pan, double-click toggle
   grab, radial menu.
5. **Do not** break the physical/virtual output split. The virtual
   monitor is still the backplane. Physical displays are still mirrorable
   "show this to someone else" surfaces.

---

## 3. Gut list

All of the following goes away in this branch. Cross-reference for
commit-splitting.

### C++
- `src/plugins/vr/worksurfacemodel.cpp/.h`
- `src/plugins/vr/worksurfacelayout.cpp/.h`
- `src/plugins/vr/spherepatchgeometry.cpp/.h`
- `src/plugins/vr/cylinderbodygeometry.cpp/.h`

### QML
- `src/plugins/vr/qml/WorkSurface3D.qml`
- `src/plugins/vr/qml/WorkSurfaceFace.qml`
- `src/plugins/vr/qml/WsEdge.qml`

### Docs
- `WORK_SURFACES.md` (replace with this pivot doc or archive)
- `WORK_SURFACES_OVERHAUL.md` if still present in history

### Integration points to clean
- `XrScene.qml` `workSurfaceRepeater` + `workSurfaceModel`
- `XrScene.qml` radial menu `Surface` submenu and handlers
  (`addPlane`, `addCube`, `addCylinder`, `addSphere`, `addPyramid`,
  layout mode submenu, `editSurface`)
- `KwinApplicationWindow` `attachedFace` / `previewFace` / `regionKind` /
  `regionRadius` properties
- `KwinApplicationWindow` `"surface"` state in the delegate state machine
  (leaves only `"vr"` and `"screen"`)
- `VrWindowManipulation.qml` snap-to-face and preview logic
- `CMakeLists.txt` entries for the removed sources

### Settings
- Any `kwinvr.kcfg` entries specific to work surfaces (none obvious, but
  audit before removing)

### What to keep
- `SpaceAllocator3D` — still the right primitive for free-space placement,
  it just won't treat work surfaces as blockers anymore.
- `VrFollowMode` — untouched; its focusOn path is central to the new flow.
- `KwinPseudoOutputMirror` — physical displays remain mirror-pinned.

---

## 4. Build list

### 4.1 Lasso (right-click drag rect)

- Today: right-click anywhere opens radial immediately (on release).
- Target: right-click-press starts a lasso rect in screen space (the
  camera's projection plane). Drag extends rect. Release opens a
  selection-aware radial menu.
- Edge cases:
  - Zero-distance drag = a simple right-click with empty selection →
    existing "empty-space radial."
  - Lasso over exactly one window → single-window radial (same as today's
    hover-a-window + radial).
  - Lasso over two or more → group radial.

### 4.2 Group relations

Introduce a `WindowGroup` abstraction — a parent `Node` that owns an
ordered list of child windows. A group has one of these modes:

| Mode     | Behavior                                                       |
|----------|----------------------------------------------------------------|
| Pinned   | Windows rigid-attached to parent. Parent is a window, not a surface. |
| Stacked  | Ordered offset; only top fully visible, others peek titlebars. |
| Camera   | Group parent follows camera (PIP). Still a `WindowGroup`, with `anchor: camera`. |

Mode transitions are radial-menu actions. A group can be:
- Broken (release all children back to free float)
- Renamed / styled (future)
- Drag-moved as a single unit (its parent window acts as the grab handle)

### 4.3 Windows-as-surfaces semantics

- Every window is implicitly a potential parent. Dropping/pinning one
  window onto another makes it a child in the parent's group.
- The "face" a child pins to is just the parent window's front plane. No
  curved UV, no separate geometry. If we ever want e.g. a side-panel, it
  becomes an offset relative to the parent's local frame.
- Groups always face the user as a unit (the parent orients; children
  inherit). No per-child facing math.

### 4.4 Camera-pin (PIP-lite)

- `WindowGroup` mode `Camera` sets the group's parent to be a child of
  the XR camera node (or its helper), with a configurable offset.
- Distance, FOV-fraction position (corner / edge / center), and opacity
  become simple properties.
- Existing `VrFollowMode` is the other half of "stuck to you" — camera-pin
  is stricter: window moves 1:1 with head. Follow-mode lags; camera-pin
  doesn't.

### 4.5 Stack UX

- Stack parent is the topmost window. Siblings below offset by a small
  `z` delta + slight down-shift so titlebars are visible.
- Click a titlebar = promote to top.
- Drag a titlebar out of the stack's bounding rect = detach from group.
- Scrollwheel on stack = cycle through (optional; defer if tricky).

---

## 5. Open decisions

Questions to settle once the user returns on the new branch. Pre-populate
with my current lean; confirm or override.

| Q | Lean | Notes |
|---|------|-------|
| Lasso shape: axis-aligned rect vs freeform | Rect | Simpler, matches 2D lasso intuition |
| Group parent = first window lassoed or topmost | Topmost (closest to camera) | Feels right; easy to change later |
| Stack direction | Forward (parent closest, children recede) | Titlebars visible at top; alt: cascade down |
| Camera-pin default position | Bottom-right, 40% FOV | HUD already claims center; corners feel right |
| Breaking a group restores prior pose? | No — drop in place | Less surprising |
| Can a window be in multiple groups? | No | Tree, not graph. Keeps state tractable |
| Radial menu: new "Group" submenu or inline? | Inline at top when selection > 0 | Context-sensitive already works this way |

---

## 6. Sequencing

Recommended commit order (each is build-green):

1. **Gut** — delete work-surface code + radial entries. Expect nothing
   visible to break; work surfaces simply vanish. Verify auto-float and
   pseudo-mirror still work.
2. **WindowGroup scaffold** — add the `WindowGroup` QML component,
   register/track-by-id, empty group actions in radial. No behavior yet,
   just data model.
3. **Pin-to-window** — radial `Pin Together` on multi-selection builds a
   group in mode `Pinned`. Drag the group parent, children follow.
4. **Stack** — mode `Stacked` + click-to-promote.
5. **Camera-pin** — mode `Camera` + corner positioning.
6. **Lasso** — replace right-click-immediate-radial with right-drag rect;
   release opens selection-aware menu.
7. **Restore stashed pieces** — RadialMenu restyle, FollowModeSetup
   recenter checkbox, `followRecenterOnFocus` kcfg (now that we have
   unconditional focus-pan from the previous branch, this becomes a
   user-facing toggle for that behavior).

Splitting this way means the user can test after step 1 to confirm the
gut didn't regress anything, and after each subsequent step to validate
one relation at a time.

---

## 7. Out of scope for this branch

- Tiling window manager semantics (auto-layout into a grid). Deferred
  until group primitives are understood.
- Rolodex / book metaphor for stacks beyond simple offset. Graphic
  flourish; add later.
- Alt-tab OSD on HUD. Still deferred — tabbox is an InternalWindow and
  needs a narrow classifier that doesn't also swallow decorations.
- Generalized per-output hide toggle. Today only Virtual-T can be hidden;
  broadening is a separate design pass.
- Monado / DRM lease cleanup when disabled outputs leave stale mirrors.
  The double-mirror bug is tracked but not this branch.
- SBS wallpaper plugin. Orphaned; already removed from the repo.

---

## 8. Reference — what already works on the base

(Do not regress these while gutting.)

- Auto-float: window whose host output is hidden flips `client.vr=true`
  and re-places via `SpaceAllocator3D`. One-way; re-showing the host does
  not snap the window back.
- Focus pull: on activation (taskbar, alt+tab, gizmo select), the focused
  window slides along its cam→window ray to sibling-average depth and
  faces the camera. Restored on defocus.
- Focus pan: `VrFollowMode.focusOn(node, camera)` animates world rotation
  to center the focused window at `followSpeed`. Works even while the
  normal `camera` binding is null-gated (hover/grab/menu). Re-faces the
  override every frame so handle rotation doesn't drift the window's
  orientation.
- Double-click on empty space latches world-grab past release; any press
  drops it.
- Single click+hold on empty space = press-and-hold world-grab.
- Space allocator search cone capped at 90° — no more spawns behind the
  user.
- Mirror un/reregisters with allocator + follow-mode on hide/show.

---

## 9. Ground truth files to re-read on branch start

Before touching anything, open these:

- `src/plugins/vr/qml/XrScene.qml` — scene composition, delegate state
  machines, radial menu handlers
- `src/plugins/vr/qml/KwinApplicationWindow.qml` — per-window delegate
  (transient chain, attachedFace / previewFace in current shape)
- `src/plugins/vr/qml/VrWindowManipulation.qml` — grab/snap pipeline,
  `rayPickPseudoOutput`, snap-on-release
- `src/plugins/vr/qml/KwinPseudoOutputMirror.qml` — physical/virtual
  output surface
- `src/plugins/vr/qml/Main.qml` — top-level input handling
- `src/plugins/vr/vrfollowmode.cpp/.h` — focusOn + onFrame override path
- `src/plugins/vr/spaceallocator3d.cpp/.h` — angular free-space finder
- `src/plugins/vr/windowmodelfilter.cpp/.h` — PrimaryWindowModelFilter
  and its exclusions (critical — do not break)

Start each build-green commit by running the existing test flow (enter
VR, spawn two terminals, alt-tab between them, toggle virtual display
hide). If any of those regress, back out before continuing.
