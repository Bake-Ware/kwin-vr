# kwin-vr — 3D Window Management Vocabulary

This document is the **testable behavior contract** for kwin-vr: an exhaustive enumeration of
every user-facing interaction that exists in the code today, expressed as numbered
Given/When/Then behaviors. It is to 3D window management what *minimize / maximize / resize /
snap* are to 2D window management — a shared vocabulary. Every PR that adds, changes, or removes
a behavior MUST cite the VOC-IDs it touches in its description, and regressions are defined as
deviations from the **Then** clause of a `Status: Working` behavior. IDs are assigned in steps of
10 so new behaviors can be inserted without renumbering; IDs are never reused or renumbered once
published.

---

## Glossary

| Noun | Meaning |
|------|---------|
| **workspace** | The whole 3D scene of managed content, parented under one grab handle node (`allWindowsGrabHandle` in `XrScene.qml`). World-grab, reset-view, and follow mode all transform this single node. |
| **gaze ray** (xray) | The head-anchored picking ray (`Xray.qml`). Offset from the head by `headgazePosition*`/`headgazeRotation*`, deflected by the pointer offset. All picking, grabbing, and pointer warping derive from it. |
| **pointer offset** | An angular deflection of the gaze ray accumulated from physical mouse motion (`VrPointerOffset`), letting the mouse "lead" the gaze. |
| **gaze reclaim** | Auto-reset of the pointer offset when the head turns far enough — the ray snaps back to head center. |
| **VR window** / detached window | A toplevel whose KWin `Window::vr` flag is true. It is parented directly under the workspace grab handle and floats freely in 3D. |
| **pseudomirror** | A 3D plane representing one KWin output (`KwinPseudoOutputMirror.qml`). Non-VR windows render on it at their 2D positions. Dragging a window off its edge detaches it to VR; dropping a VR window onto it re-attaches it to that screen. |
| **virtual screen** | A headless KWin virtual output created on VR entry (`KwinVirtualScreenHandle`) that serves as the default 2D home for windows; its pseudomirror is usually hidden. |
| **world-grab** | Grabbing the workspace grab handle itself, so the entire scene follows the gaze ray. |
| **grab handle** | The node actually moved when an object is grabbed. A VR window is its own handle; a window lying on a pseudomirror resolves to the pseudomirror as handle. |
| **ZStack** (z-stacking) | Depth-sorting of co-planar surfaces (windows on a pseudomirror, transient popups over their parent) along local Z by stacking order (`ZStacker`). |
| **stack** (cascade) | A WindowSnapManager grouping: windows dropped on the center of another VR window cascade behind/onto it (`stackedOnto` / `stackIndex`). |
| **dock / snap** | WindowSnapManager edge actions: dropping a dragged VR window on the left/right/top/bottom band of another VR window aligns it edge-to-edge. |
| **telegraph** | The translucent rectangle previewing the landing pose of a pending snap/stack. |
| **HUD plane** | A camera-pinned surface in front of and below the gaze where overlay windows (panel/dock, notifications, OSD, applet popups) are projected (`hudNode` in `XrScene.qml`). |
| **Xray HUD** | A separate debug panel attached to the ray showing pick info (`XrayHud.qml`); toggled by the "VR Hud" shortcut. |
| **follow mode** | Workspace auto-rotation that swings windows back into view when the user looks away (`VrFollowMode`). |
| **head scroll** | Scrolling generated from head rotation while a binding (default middle mouse) is held (`VrHeadScroll`). |
| **radial menu** | The 5-button pie menu opened by right-clicking empty space. |
| **ppu** | Pixels per unit (cm). Converts 2D pixel geometry to 3D size; default 20 px/cm. |
| **leasable output** | A physical display (HMD) offered to the OpenXR runtime via DRM leasing. |

Config keys below are entries of `src/plugins/vr/kwinvr.kcfg` (file `~/.config/kwinvr`), written
as `name (default)`.

---

## GAZE — ray, cursor, picking, pointer offset, head scroll

### VOC-GAZE-010: Head-anchored gaze ray
**Given** VR mode active **When** the user moves their head **Then** the picking ray follows the camera with a fixed local offset (default 15 cm right, 10 cm down, 5 cm forward) and angular bias (yaw 4°, pitch 6°), so the ray originates near the user's "chin" and points where they look.
- Input source(s): head-pose
- Config keys: `headgazePositionX (15.0)`, `headgazePositionY (-10.0)`, `headgazePositionZ (-5.0)`, `headgazeRotationHorizontal (4.0)`, `headgazeRotationVertical (6.0)`
- Code: src/plugins/vr/qml/Xray.qml:17-23, src/plugins/vr/qml/XrScene.qml:318-336
- Status: Working

### VOC-GAZE-020: Mouse deflects the ray (pointer offset)
**Given** `blockOtherPointerMotion` is **false** **When** the physical mouse moves by (dx,dy) pixels **Then** the gaze ray deflects by `dx×sensitivity` degrees yaw and `dy×sensitivity` degrees pitch, clamped to ±`mouseOffsetMaxDegrees`, letting the mouse steer the cursor independently of the head.
- Input source(s): mouse
- Config keys: `blockOtherPointerMotion (true — feature OFF by default)`, `mouseOffsetSensitivity (0.1 °/px)`, `mouseOffsetMaxDegrees (50.0)`
- Code: src/plugins/vr/vrpointeroffset.cpp:20-45, src/plugins/vr/qml/XrScene.qml:74-80, src/plugins/vr/qml/Xray.qml:20-23
- Status: Working

### VOC-GAZE-030: Gaze reclaim
**Given** pointer offset enabled and non-zero **When** the head rotates more than `gazeReclaimThreshold × mouseOffsetMaxDegrees` degrees (default 0.8 × 50 = 40°) away from the reference orientation captured when the offset was last centered **Then** the pointer offset resets to (0,0) — the ray snaps back to head center.
- Input source(s): head-pose
- Config keys: `gazeReclaimEnabled (true)`, `gazeReclaimThreshold (0.8)`, `mouseOffsetMaxDegrees (50.0)`
- Code: src/plugins/vr/qml/XrScene.qml:82-115, src/plugins/vr/vrpointeroffset.cpp:148-156
- Status: Working

### VOC-GAZE-040: Ray visual is invisible when idle, green when grabbing
**Given** default colors **When** nothing is grabbed **Then** the cone-shaped ray model is fully transparent (idle color alpha = 0 ⇒ `visible: false`); **When** an object is grabbed **Then** the ray renders in the grab color (#459901) at the grabbed object's distance.
- Input source(s): n/a (visual feedback)
- Config keys: `headgazeColor (#00000000)`, `headgazeGrabColor (#459901)`
- Code: src/plugins/vr/qml/Xray.qml:26-29, src/plugins/vr/qml/VrRayController.qml:19-49, src/plugins/vr/qml/VrRay.qml:12-25
- Status: Working

### VOC-GAZE-050: Ray length tracks pick / grab distance
**Given** the ray is visible **Then** its length equals the grabbed object's distance when grabbing, else the last pick hit distance when hovering, else the 300 cm default.
- Input source(s): n/a (visual feedback)
- Config keys: none
- Code: src/plugins/vr/qml/VrRayController.qml:19-27, src/plugins/vr/qml/Xray.qml:24
- Status: Working

### VOC-GAZE-060: Ray picking with per-object veto
**Given** ray enabled **When** the ray transform changes **Then** all scene objects under the ray are picked (`rayPickAll`), and the topmost object whose optional `onPick(pickResult)` returns true (e.g. HUD windows reject picks landing in their shadow margin) becomes `hoveredObject`/`lastPick`.
- Input source(s): head-pose / mouse (via offset)
- Config keys: none
- Code: src/plugins/vr/qml/VrPicking.qml:34-73, src/plugins/vr/qml/VrHudWindow.qml:120-139
- Status: Working

### VOC-GAZE-070: 3D cursor sprite on hovered surface
**Given** cursor enabled (default on) **When** the ray hovers an object **Then** a textured quad showing the real KWin cursor image (with hotspot correction) is drawn at the hit point, slightly lifted along the surface normal (`hoverDistance` −0.015) and oriented to the hovered surface; while a window is being moved/resized the cursor instead follows the ray–window-plane intersection.
- Input source(s): head-pose / mouse
- Config keys: none (toggle via VOC-SHORTCUT-090)
- Code: src/plugins/vr/qml/VrCursorManager.qml:23-69, src/plugins/vr/qml/VrKwinCursor.qml:11-41
- Status: Working

### VOC-GAZE-080: Hover warps the 2D pointer into the hovered window
**Given** no grab and no move/resize in progress **When** the ray hovers any recognized surface type (HUD window, pseudomirror, thumbnail, Wayland surface, decoration, internal window) **Then** the pick UV is converted to that surface's 2D coordinates and the KWin pointer is warped there, so 2D clicks land where the ray points.
- Input source(s): head-pose / mouse
- Config keys: none
- Code: src/plugins/vr/qml/VrPointerHandler.qml:107-123, src/plugins/vr/qml/VrHoverState.qml:33-114, src/plugins/vr/qml/KwinPseudoOutputMirror.qml:27-39
- Status: Working

### VOC-GAZE-090: Move/resize pointer follows ray-plane intersection
**Given** a window is in an interactive move/resize **When** the ray moves **Then** the 2D pointer position is computed from the ray's intersection with the window's 3D plane (extrapolated beyond the window bounds), enabling 2D-style move/resize driven by gaze.
- Input source(s): head-pose / mouse
- Config keys: none
- Code: src/plugins/vr/qml/VrPointerHandler.qml:28-105
- Status: Working

### VOC-GAZE-100: Hovered window receives forced pointer focus
**Given** VR active **When** a surface with a client is hovered or being moved/resized **Then** that client is reported to KWin's pointer as the hovered window (bypassing 2D hit testing), so pointer events route to the window under the ray.
- Input source(s): head-pose
- Config keys: none
- Code: src/plugins/vr/qml/VrPointerHandler.qml:140-148, src/plugins/vr/kwinvrhoveredwindowresolver.cpp:15-27
- Status: Working

### VOC-GAZE-110: Pointer motion inhibited briefly after click
**Given** `pointerInhibitDelay` ≥ 0 **When** a mouse button is pressed **Then** physical pointer-motion events are swallowed for the next `pointerInhibitDelay` ms (default 100), preventing click-point drift from hand jitter; −1 disables.
- Input source(s): mouse
- Config keys: `pointerInhibitDelay (100)`
- Code: src/plugins/vr/kwinvrinputfilter.cpp:112-123, src/plugins/vr/qml/Main.qml:23-27
- Status: Working

### VOC-GAZE-120: Non-VR pointer motion blocked
**Given** VR active **When** any input device other than the VR virtual device emits pointer motion **Then** the motion is blocked unless the pointer is constrained (e.g. a game has locked it) — the VR layer owns absolute pointer positioning.
- Input source(s): mouse/touchpad
- Config keys: none (always on while VR runs; `blockOtherPointerMotion (true)` only gates the offset alternative, VOC-GAZE-020)
- Code: src/plugins/vr/relativemotionblocker.cpp:24-33, src/plugins/vr/qml/XrScene.qml:70-72
- Status: Working

### VOC-GAZE-130: Head scroll
**Given** a head-scroll binding (default `MouseMiddle`) is held **When** the head pitches/yaws beyond `headScrollThreshold` degrees **Then** vertical/horizontal wheel events proportional to the angle delta (× speed multipliers) are injected via the VR input device, scrolling the focused window; pointer-position updates from hover/move are suspended while head scroll is active.
- Input source(s): head-pose + mouse/keyboard (activation binding)
- Config keys: `headScrollBindings (MouseMiddle)`, `verticalHeadScrollSpeed (40.0)`, `horizontalHeadScrollSpeed (40.0)`, `headScrollThreshold (0.1°)`
- Code: src/plugins/vr/vrheadscroll.cpp:121-157, src/plugins/vr/vrheadscrollfilter.cpp:182-246, src/plugins/vr/qml/XrScene.qml:229-236, src/plugins/vr/qml/VrPointerHandler.qml:50-72
- Status: Working

---

## GRAB — grabbing windows, depth control

### VOC-GRAB-010: Grab/release the hovered window (shortcut)
**Given** the ray hovers a window's grab handle and nothing is grabbed **When** the "Grab Window" shortcut fires **Then** the handle is grabbed: its pose relative to the ray is captured and it follows the ray rigidly. **When** the shortcut fires again (anything grabbed) **Then** it is released in place.
- Input source(s): shortcut (default Ctrl+Meta+E, see VOC-SHORTCUT-030)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:185, src/plugins/vr/qml/XrScene.qml:156-161, src/plugins/vr/qml/Xray.qml:58-64,168-174
- Status: Working

### VOC-GRAB-020: Any button press releases a grab
**Given** an object is grabbed **When** any mouse button is pressed **Then** the grab releases first; if the released grab was the world-latch and a window is under the cursor, the click passes through to that window; if a KWin move/resize is in progress the press passes through so KWin can finish the move.
- Input source(s): mouse (any button)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:75-91, src/plugins/vr/qml/XrScene.qml:147-154
- Status: Working

### VOC-GRAB-030: Meta+press grabs a desktop/dock screen
**Given** the ray hovers a desktop or dock surface and nothing is grabbed **When** any mouse button is pressed with Meta held **Then** the hovered surface's grab handle (its pseudomirror — i.e. the whole screen plane) is grabbed and follows the ray until the button is released.
- Input source(s): mouse + keyboard (Meta modifier)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:93-98,119-123, src/plugins/vr/qml/XrScene.qml:208-219, src/plugins/vr/qml/VrHoverState.qml:116-119
- Status: Working

### VOC-GRAB-040: Up/Down push-pull while grabbed
**Given** an object is grabbed **When** the Up arrow key is held **Then** the object moves away from the user along the ray at 90 cm/s; **When** Down is held **Then** it moves toward the user at 90 cm/s; releasing the key stops the motion; releasing the grab clears both.
- Input source(s): keyboard
- Config keys: none (rate hardcoded `frameTime * 90`)
- Code: src/plugins/vr/qml/Main.qml:42-65, src/plugins/vr/qml/Xray.qml:36-53,80-82
- Status: Working

### VOC-GRAB-050: Scroll-to-depth on grabbed object
**Given** a detached VR window or the world is grabbed **When** the wheel scrolls (no modifier) **Then** the grab distance changes by `grabScrollSensitivity` cm per notch (scroll up = closer), refusing steps that would leave the [`grabScrollMinDistance`, `grabScrollMaxDistance`] range; grabbed non-VR objects (pseudomirrors) ignore depth scroll.
- Input source(s): mouse wheel
- Config keys: `grabScrollSensitivity (3.0 cm)`, `grabScrollMinDistance (10.0 cm)`, `grabScrollMaxDistance (500.0 cm)`
- Code: src/plugins/vr/qml/Main.qml:140-153, src/plugins/vr/qml/XrScene.qml:169-183, src/plugins/vr/qml/Xray.qml:84-93
- Status: Working

### VOC-GRAB-060: KWin move of a VR window auto-grabs it onto the ray
**Given** a detached VR window starts a KWin interactive **move** (decoration drag, Meta+drag, titlebar menu, hotkey) **Then** the window is grabbed by the ray, turned to face the camera, and rotated around the camera so the ray passes through the cursor's position inside the window (fullscreen windows use the normalized press position); ending the move releases the grab.
- Input source(s): mouse / keyboard / window menu (anything that starts a KWin move)
- Config keys: none
- Code: src/plugins/vr/qml/VrWindowManipulation.qml:62-93,164-178, src/plugins/vr/qml/KwinTransientWindow.qml:39-48, src/plugins/vr/qml/Xray.qml:101-166
- Status: Working

### VOC-GRAB-070: Grabbed object follows ray rigidly
**Given** an object is grabbed **When** the ray's scene transform changes (head or mouse) **Then** the captured relative pose is re-applied every frame, so the object keeps its distance and orientation relative to the ray.
- Input source(s): head-pose / mouse
- Config keys: none
- Code: src/plugins/vr/qml/Xray.qml:113-118,168-174
- Status: Working

### VOC-GRAB-080: Pointer warping suspended during grab
**Given** an object is grabbed **Then** hover pointer-warping (VOC-GAZE-080/090) and the VRWindow input bridge are disabled until release, so the 2D pointer does not chase the ray during transport.
- Input source(s): n/a (state interaction)
- Config keys: none
- Code: src/plugins/vr/qml/VrPointerHandler.qml:50-72,132-137
- Status: Working

---

## WORLD — world-grab, realign, reset view

### VOC-WORLD-010: Left-press on empty space starts a world-grab
**Given** the ray hovers nothing and nothing is grabbed **When** the left button is pressed **Then** the entire workspace (all windows + pseudomirrors) is grabbed immediately and follows the ray.
- Input source(s): mouse (left button on empty space)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:100-108, src/plugins/vr/qml/XrScene.qml:156-161
- Status: Working

### VOC-WORLD-020: Drag-release ends the world-grab
**Given** a world-grab started by left-press (VOC-WORLD-010) **When** the left button is released after the cursor moved from the press position **Then** the world is released where dragged.
- Input source(s): mouse
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:125-132
- Status: Working

### VOC-WORLD-030: Click-without-motion latches the world-grab
**Given** a world-grab started by left-press **When** the button is released with zero cursor motion **Then** the world stays grabbed (latched) and follows the gaze hands-free until the next button press (VOC-GRAB-020), which releases it and, if over a window, forwards the click.
- Input source(s): mouse
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:71-74,100-108,125-132,76-85
- Status: Working

### VOC-WORLD-040: Grab All shortcut grabs/releases the world
**Given** nothing grabbed **When** the "Grab All Windows" shortcut fires **Then** the workspace grab handle is grabbed (same as VOC-WORLD-010 but from anywhere); fired again it releases.
- Input source(s): shortcut (default Shift+Meta+E, see VOC-SHORTCUT-040)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:186, src/plugins/vr/qml/XrScene.qml:156-161
- Status: Working

### VOC-WORLD-050: Reset view recenters the workspace
**When** "Reset View" triggers (shortcut, radial menu "Recenter", or startup timer) **Then** the workspace origin moves to the current head position and the grab handle is placed `distance` cm straight ahead, rotated to match the camera — the whole layout re-centers in front of the user, preserving relative window arrangement.
- Input source(s): shortcut (Ctrl+Meta+T) / radial menu / automatic
- Config keys: `distance (100)`
- Code: src/plugins/vr/qml/XrScene.qml:54,410-416, src/plugins/vr/qml/Main.qml:192
- Status: Working

### VOC-WORLD-060: Automatic reset shortly after VR entry
**Given** `resetViewDelay` ≥ 0 **When** VR mode has been up for `resetViewDelay` seconds **Then** a one-shot reset-view fires (compensating for the headset pose at session start); negative value disables; follow mode is suppressed until the timer fires.
- Input source(s): automatic
- Config keys: `resetViewDelay (2.0 s)`
- Code: src/plugins/vr/qml/XrScene.qml:25-33,428-431
- Status: Working

### VOC-WORLD-070: Realign hovered window to face the user
**Given** the ray hovers a grab handle **When** the "Realign VR Window" shortcut fires **Then** the hovered handle (window or whole pseudomirror) rotates in place to face the camera, preserving its roll.
- Input source(s): shortcut (default Ctrl+Meta+W, see VOC-SHORTCUT-020)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:184, src/plugins/vr/qml/XrScene.qml:140-145
- Status: Working

---

## RESIZE — resizing detached VR windows

### VOC-RESIZE-010: Shift+wheel resizes width
**Given** a detached VR window is grabbed **When** the wheel scrolls with Shift held **Then** the window's 2D width grows/shrinks by `grabResizeSensitivity` px per notch (up = wider, floor 1 px), and the 3D plane resizes accordingly.
- Input source(s): mouse wheel + keyboard (Shift)
- Config keys: `grabResizeSensitivity (40.0 px)`
- Code: src/plugins/vr/qml/Main.qml:140-153, src/plugins/vr/qml/XrScene.qml:186-193, src/plugins/vr/kwinvrhelpers.cpp:135-143
- Status: Working

### VOC-RESIZE-020: Ctrl+wheel resizes height
**Given** a detached VR window is grabbed **When** the wheel scrolls with Ctrl held **Then** the window's 2D height changes by `grabResizeSensitivity` px per notch.
- Input source(s): mouse wheel + keyboard (Ctrl)
- Config keys: `grabResizeSensitivity (40.0 px)`
- Code: src/plugins/vr/qml/Main.qml:146-150, src/plugins/vr/qml/XrScene.qml:186-193
- Status: Working

### VOC-RESIZE-030: Touchpad pinch resizes uniformly
**Given** a detached VR window is grabbed **When** a touchpad pinch gesture updates **Then** the window is resized by the incremental pinch scale ratio in both dimensions (uniform zoom); pinch events are consumed by VR while active.
- Input source(s): touchpad pinch gesture
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:162-180, src/plugins/vr/qml/XrScene.qml:196-206, src/plugins/vr/kwinvrinputfilter.cpp:125-159
- Status: Unverified — code path complete; no record of device testing

---

## SNAP — natural-drag dock + stack (issue #14)

Ground truth for design intent: `doc/DOCK_AND_STACK_WIP.md` (locked-design table). The current
implementation (UV-band ray-pick in `WindowSnapManager.qml`) post-dates and **diverges from**
parts of that table — divergences are flagged per behavior. The WIP doc records commit and
adhesion as "not working" at its last user test; code has changed since without a recorded
retest, so commit-path behaviors are at best WIP.

### VOC-SNAP-010: Snap intent from edge bands while dragging
**Given** a detached VR window is grabbed (dragged) **When** the ray's first hit on another VR window (skipping the dragged window's own stack) lands within the outer 25% UV band of an edge **Then** the snap intent becomes SnapLeft/SnapRight/SnapAbove/SnapBelow for that edge; the UV is recomputed against the target's stack-root plane to avoid jitter; intent changes are logged (`Snap intent: <Action> → <class>`).
- Input source(s): mouse/head (drag)
- Config keys: none (`edgeBand` hardcoded 0.25)
- Code: src/plugins/vr/qml/WindowSnapManager.qml:33,277-341
- Status: Working (logs confirmed per WIP doc). Diverges from locked design: detection is ray-UV bands, not per-frame quad overlap with ≥3-quad threshold.

### VOC-SNAP-020: Stack intent from center zone
**Given** same drag context **When** the hit UV is in the central region (inside all four 25% bands) **Then** intent becomes Stack on the target's stack root.
- Input source(s): mouse/head (drag)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:277-283
- Status: Working. Diverges from locked design: stack target is the stack **root** (bottommost), not the topmost member.

### VOC-SNAP-030: Telegraph ghost previews landing pose
**Given** a snap/stack intent is active **Then** a translucent cyan rectangle (opacity 0.4) renders at the computed landing offset on the target's plane, sized to the landing size, rotated to the target's rotation; it disappears when intent clears.
- Input source(s): n/a (visual feedback)
- Config keys: `zSurfaceMarginTop (1.0 cm)` (plane lift)
- Code: src/plugins/vr/qml/XrScene.qml:518-547, src/plugins/vr/qml/WindowSnapManager.qml:197-250
- Status: Working (user confirmed "look pretty ok" per WIP doc)

### VOC-SNAP-040: Surface adhesion during drag
**Given** a snap/stack intent is active **When** each pick update runs **Then** the dragged window is laid onto the target root's plane at the hit point (`z = zSurfaceMarginTop` forward) and assumes the target's rotation, with the grab pose re-captured so it stays adhered between frames.
- Input source(s): mouse/head (drag)
- Config keys: `zSurfaceMarginTop (1.0 cm)`
- Code: src/plugins/vr/qml/WindowSnapManager.qml:327-341
- Status: WIP — WIP doc records "no surface adhesion visible" at last test; current pose-recapture code is newer and unretested.

### VOC-SNAP-050: Commit side-snap on release
**Given** a SnapLeft/Right intent at grab release **Then** the dragged window is resized to match the target's **height** (keeping its own width), positioned edge-adjacent to the target (offset ±(tw/2+dw/2)), and rotated to the target's plane. SnapAbove/Below symmetric: width matched, own height kept, offset ±(th/2+dh/2). A `Snap commit:` log line records the action.
- Input source(s): mouse (release of drag)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:223-239,343-374,486-514
- Status: WIP — WIP doc's last test: "window does not resize or move on release"; hypotheses H1–H5 unresolved.

### VOC-SNAP-060: Commit stack on release
**Given** a Stack intent at grab release **Then** the dragged window is resized to the target's full size, gets `stackedOnto = target` and the next free `stackIndex`, and is placed at the cascade offset `(+step·k, −step·k, +step·k)` where `step = zSurfaceMarginTop` and k = stackIndex (right + down + forward cascade).
- Input source(s): mouse (release of drag)
- Config keys: `zSurfaceMarginTop (1.0 cm)`
- Code: src/plugins/vr/qml/WindowSnapManager.qml:216-222,343-374
- Status: Working — `_commitSnap` verified live on the flat substrate (kwinvr-testFlatSnapReplay); the release-trigger path (`_grabWatcher` firing at real drag end) still has the VOC-SNAP-050 uncertainty.

### VOC-SNAP-070: First snap snapshots original size
**Given** a window that has never been snapped **When** a snap/stack commits **Then** its pre-snap frame size is stored in `preSnapGeom`.
- Input source(s): n/a (side effect of commit)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:354-355, src/plugins/vr/qml/KwinTransientWindow.qml:26-28
- Status: WIP — snapshot is captured but **never restored anywhere**; locked design's "restored on detach" is unimplemented.

### VOC-SNAP-080: Dragging a stack root carries its members
**Given** a VR-floating stack root is grabbed **Then** all windows stacked onto it are temporarily reparented under it (transform inheritance), so the whole cascade moves rigidly with the drag; on release they are reparented back preserving scene pose.
- Input source(s): mouse/head (drag)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:387-422,486-514
- Status: Unverified. Diverges from locked design: group move is unconditional on root-drag, not Shift+drag.

### VOC-SNAP-090: Dragging a stack member detaches it
**Given** a stacked (non-root) window is grabbed **Then** it is immediately detached from its stack: its `stackedOnto`/`stackIndex` clear, higher siblings shift down one index, and the remaining cascade repositions; the detached window may re-stack on a new target at release.
- Input source(s): mouse/head (drag)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:100-130,493-497
- Status: Unverified

### VOC-SNAP-100: Click promotes within a stack
**Given** a left-button release with no drag having started during that press **When** the currently active KWin window is part of a stack **Then** it is promoted: a member moves to the top cascade index (siblings above shift down); clicking the root rotates the stack — the top member becomes the new root anchored at the root's pose, the old root becomes the top member.
- Input source(s): mouse (click)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:136-195,453-484
- Status: Unverified

### VOC-SNAP-110: Stack root dropped on a pseudomirror unstacks everyone
**Given** a stack root with carried members is mid-drag **When** the root's `client.vr` flips false (it landed on a screen, VOC-MIRROR-050) **Then** members are released from the drag, their stack state cleared, and each member is sent to a screen too (`vr = false`) instead of being dragged into the screen frame.
- Input source(s): mouse/head (drag onto pseudomirror)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:428-448
- Status: Unverified

### VOC-SNAP-120: Esc cancels snap intent
**Locked design**: pressing Esc during a drag cancels the pending snap intent while the drag continues.
- Input source(s): keyboard
- Config keys: none
- Code: not implemented (no Esc handling in WindowSnapManager.qml)
- Status: WIP — designed, absent from code.

### VOC-SNAP-130: Snapping to an occupied slot redirects to the occupant
**Locked design**: snap-slot collision "falls out naturally" — overlap with the occupying neighbor makes its own bands dictate the action. In the current UV implementation this holds implicitly: the first ray hit is whatever window occupies the space.
- Input source(s): mouse/head (drag)
- Config keys: none
- Code: src/plugins/vr/qml/WindowSnapManager.qml:297-309
- Status: Unverified

### VOC-SNAP-140: Stack-focus signal promotion (dead path)
`KwinTransientWindow` declares `stackFocusRequested()` and `XrScene` routes it to `promoteStackMember`, but **nothing ever emits the signal** — promotion only happens via the click-watcher (VOC-SNAP-100).
- Input source(s): none (dead code)
- Config keys: none
- Code: src/plugins/vr/qml/KwinTransientWindow.qml:35-37, src/plugins/vr/qml/XrScene.qml:568
- Status: Buggy — declared interaction with no emitter; either emit on `client.active` or remove.

### VOC-SNAP-150: A stack stays one rigid container after commit
**Given** a committed stack **Then** the container invariant persists past the commit: a root client resize propagates to every member (members re-match the root's full frame size); a member resizing itself is snapped back to the root size; and if the root's node moves or rotates outside a drag (e.g. the space allocator re-places it after a resize), members re-assert their cascade offset relative to it. Without this, any later client resize drifts the stack layout apart (#18).
- Input source(s): n/a (client/compositor-driven geometry changes)
- Config keys: `zSurfaceMarginTop (1.0)`
- Code: src/plugins/vr/qml/KwinTransientWindow.qml:36-86
- Status: Working

---

## MIRROR — pseudomirrors, ZStacker, drag on/off screen

### VOC-MIRROR-010: Every output gets a pseudomirror plane
**Given** VR mode active **When** an output exists (or appears) **Then** a pseudomirror node is created for it: a blue rounded-rect screen frame sized `output.geometry / ppu`, placed at a free position on the viewing sphere (VOC-PLACE-010) facing the user, registered with follow mode and the space allocator.
- Input source(s): n/a (output hotplug / VR entry)
- Config keys: `ppu (20)`
- Code: src/plugins/vr/qml/XrScene.qml:477-516, src/plugins/vr/qml/KwinPseudoOutputMirror.qml:17-58, src/plugins/vr/qml/VrScreenFrame.qml:12-40
- Status: Working

### VOC-MIRROR-020: Non-VR windows lie on their output's pseudomirror
**Given** a toplevel with `vr == false` **Then** its 3D item is parented to the pseudomirror of its KWin output, positioned by its 2D frame geometry relative to the output (center-offset / ppu), rotation identity — the screen's layout is mirrored 1:1 in 3D.
- Input source(s): n/a (window state)
- Config keys: `ppu (20)`
- Code: src/plugins/vr/qml/XrScene.qml:606-625
- Status: Working

### VOC-MIRROR-030: Z-stacking on the mirror by KWin stacking order
**Given** multiple windows on a pseudomirror **Then** a ZStacker sorts them along local Z by `stackingOrder`, separating each by its Z margins (window depth + flexible spacing), with the screen frame at the bottom (0.2 top margin); raise/lower in 2D reorders depth in 3D.
- Input source(s): n/a (derived from 2D stacking)
- Config keys: `zWindowMarginTop (1.0)`, `zWindowMarginBottom (0.0)`, `minTransientNormalSpacing (4.0)`
- Code: src/plugins/vr/qml/KwinPseudoOutputMirror.qml:41-57, src/plugins/vr/zstacker.cpp:175-270
- Status: Working

### VOC-MIRROR-040: Dragging past the screen edge detaches a window to VR
**Given** a non-VR, non-transient window is in a KWin interactive move **When** the (ray-driven) pointer goes more than 80 px beyond the output bounds — pointer clamped to the screen until then (barrier) — and the ray is not over the window's own pseudomirror **Then** the window detaches: it is grabbed and aligned to the ray at the cursor point, `vr = true`, its 2D position pinned to the output origin (X11 popup placement), and a prior maximization is re-applied so the detached window keeps its maximized size.
- Input source(s): mouse/head (window drag)
- Config keys: none (`windowDetachMargin` hardcoded 80 px)
- Code: src/plugins/vr/qml/VrWindowManipulation.qml:27-60,199-232, src/plugins/vr/qml/VrBarrierConstraint.qml:25-44
- Status: Working

### VOC-MIRROR-050: Dropping a grabbed VR window onto a pseudomirror re-attaches it
**Given** a detached VR window is grabbed **When** any ray pick hits a pseudomirror's screen frame **Then** the 2D pointer warps to the frame's hit position, the window is sent to that output (`sendClientToScreen`), the grab releases, and `vr = false` — the window lands on the screen where the ray points. (Fires immediately on ray-over-frame, not on release.)
- Input source(s): mouse/head (drag over screen frame)
- Config keys: none
- Code: src/plugins/vr/qml/VrWindowManipulation.qml:180-197,244-269
- Status: Working

### VOC-MIRROR-060: Virtual screen's pseudomirror hidden
**Given** `hideVirtualDisplay` true (default) **Then** the pseudomirror for the VR virtual output (`Virtual-<name>`) is removed from the scene graph entirely (parent null) — its windows are still tracked (map lookup keeps re-attach working), but no floating empty frame is visible.
- Input source(s): n/a (config)
- Config keys: `hideVirtualDisplay (true)`
- Code: src/plugins/vr/qml/XrScene.qml:482-486,501-515
- Status: Working

### VOC-MIRROR-065: Hidden mirror releases its allocator/follow-mode slot
**Given** a pseudomirror leaves the scene graph (hidden per VOC-MIRROR-060, or destroyed) **Then** it unregisters from the space allocator and follow mode, freeing its (typically front-center) angular slot for future placements; re-showing it re-registers.
- Input source(s): n/a (config / output hotplug)
- Config keys: `hideVirtualDisplay (true)`
- Code: src/plugins/vr/qml/VrWorkspaceScene.qml:498-515
- Status: Working

### VOC-MIRROR-070: Transient windows stack in front of their parent
**Given** a window has transient children (menus, popups, dialogs) **Then** they render as planes Z-stacked in front of the parent window — menus first, then transient normal windows, each separated by computed Z margins; popups may extend beyond screen bounds for VR windows (custom popup bounds resolver unions the transient chain geometry).
- Input source(s): n/a (window hierarchy)
- Config keys: `zSurfaceMarginTop (1.0)`, `zSurfaceMarginBottom (0.0)`, `minTransientNormalSpacing (4.0)`
- Code: src/plugins/vr/qml/KwinTransientWindow.qml:93-135, src/plugins/vr/kwinvr.cpp:331-342, src/plugins/vr/windowmodelfilter.cpp:417-445
- Status: Working

### VOC-MIRROR-080: Windows auto-float when their host mirror disappears
**Given** a toplevel with `vr == false` **When** its host output's pseudomirror is absent or detached from the scene graph (hidden virtual display, output not rendered) — at window birth or later **Then** the window promotes itself to `vr = true` and is placed in free space by the allocator (VOC-PLACE-010 path), facing the viewpoint. The promotion is **one-way**: re-showing the mirror does not snap the window back (auto-floated windows stay floating).
- Input source(s): n/a (output/mirror state)
- Config keys: `hideVirtualDisplay (true)`
- Code: src/plugins/vr/qml/VrWorkspaceScene.qml:601-651
- Status: Working

---

## PLACE — automatic 3D placement (SpaceAllocator3D)

### VOC-PLACE-010: New screens placed at the nearest free angular slot
**Given** existing tracked objects (pseudomirrors, VR windows) **When** a new pseudomirror is created **Then** the allocator projects all tracked objects to angular bounds from the viewpoint and scans candidate positions on the viewing sphere — center first, then concentric rings, **capped at 90° from forward** (front hemisphere only; nothing ever spawns behind the user) — at `distance` cm, returning the first slot whose angular bounds (object size + `spacing` 0.1 rad) overlap nothing; the mirror is placed there facing the viewpoint.
- Input source(s): n/a (automatic)
- Config keys: `distance (100)`; spacing/granularity hardcoded (0.1 / 0.1) in XrScene
- Code: src/plugins/vr/spaceallocator3d.cpp:265-301,225-263, src/plugins/vr/qml/XrScene.qml:468-475,488-495
- Status: Working

### VOC-PLACE-020: Placed objects become obstacles
**Given** any pseudomirror or VR application window exists **Then** it is registered with the allocator (its `itemSize` = frame size / ppu, 0×0 while on a mirror) so future placements avoid it.
- Input source(s): n/a (automatic)
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:577-589,494, src/plugins/vr/spaceallocator3d.cpp:104-121
- Status: Working

### VOC-PLACE-030: Fallback placement straight ahead
**Given** no free slot exists anywhere in the front hemisphere **Then** the allocator returns the point directly forward at `distance` (overlapping whatever is there).
- Input source(s): n/a (automatic)
- Config keys: `distance (100)`
- Code: src/plugins/vr/spaceallocator3d.cpp:299-300
- Status: Working

### VOC-PLACE-040: Detached windows are NOT auto-placed
**Given** a window detaches to VR **Then** its position comes from the ray/cursor alignment (VOC-MIRROR-040), not from the allocator — `findFreePosition` is only called for pseudomirrors today.
- Input source(s): n/a (documenting a non-behavior)
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:488-495 (only call site)
- Status: Working (by design today; allocator is general-purpose for future use)

---

## FOLLOW — follow mode

### VOC-FOLLOW-010: Follow mode enabled by default, toggled from the radial menu
**Given** `followEnabled` (default true) **Then** follow mode starts active on VR entry; the radial menu's "Follow" button toggles it at runtime and shows its state via a red border.
- Input source(s): radial menu / config
- Config keys: `followEnabled (true)`
- Code: src/plugins/vr/qml/XrScene.qml:406-408,363-398
- Status: Working

### VOC-FOLLOW-020: Looking away swings windows back into view
**Given** follow mode on and no tracked node (pseudomirror or VR window) within `followFovH`×`followFovV` degrees of the gaze for more than `followDelay` seconds **Then** the workspace rotates around the user's head toward the closest tracked node, slerping at `followSpeed`, keeping each node's distance from the head (arc interpolation) and turning the workspace to face the user.
- Input source(s): head-pose
- Config keys: `followFovH (40)`, `followFovV (20)`, `followDelay (0.5 s)`, `followSpeed (2.0)`
- Code: src/plugins/vr/vrfollowmode.cpp:281-373
- Status: Working

### VOC-FOLLOW-030: Follow stops when the window is centered
**Given** follow rotation in progress **When** the closest node comes within `followStopFovH`×`followStopFovV` degrees of the gaze **Then** rotation stops (hysteresis: start at 40°/20°, stop at 4°/4°).
- Input source(s): head-pose
- Config keys: `followStopFovH (4)`, `followStopFovV (4)`
- Code: src/plugins/vr/vrfollowmode.cpp:296-302
- Status: Working

### VOC-FOLLOW-040: Follow is suppressed during interactions
**Given** follow mode on **Then** following is inhibited while: the startup auto-align timer runs, head scroll is active, anything is grabbed, a window is being moved/resized, the radial menu is open, or (when not already rotating) the ray hovers any object.
- Input source(s): n/a (state interaction)
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:426-453
- Status: Working

### VOC-FOLLOW-050: World-up alignment option
**Given** `followWorldUpAlignment` true **Then** follow rotation aligns windows' up with the world horizon instead of the camera's roll.
- Input source(s): config
- Config keys: `followWorldUpAlignment (false)`
- Code: src/plugins/vr/vrfollowmode.cpp:349-352
- Status: Working

### VOC-FOLLOW-060: Workspace origin follows head position
**Given** follow mode on **Then** the workspace root continuously tracks the camera's scene position (rotation pivots stay on the head); toggling follow on snaps the origin to the head once.
- Input source(s): head-pose
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:408,418-424
- Status: Working

---

## HUD — camera-pinned overlay surfaces

### VOC-HUD-010: Overlay windows pinned to the HUD plane
**Given** VR active **Then** dock/panel + tooltips, notifications, OSD windows, and applet popups (plus their transient descendants, chain depth ≤ 10) render on a camera-pinned plane placed at `hudDistanceFraction`% of workspace distance, tilted `hudVerticalAngle`° below center, scaled by `hudScaleH/V`, optionally cylinder-curved; each window keeps its relative 2D position mapped onto the surface.
- Input source(s): n/a (window type routing)
- Config keys: `hudDistanceFraction (70)`, `hudVerticalAngle (12)`, `hudScaleH (0.8)`, `hudScaleV (0.8)`, `hudCurvature (0.0)`
- Code: src/plugins/vr/qml/XrScene.qml:273-316, src/plugins/vr/qml/VrHudWindow.qml:17-150, src/plugins/vr/windowmodelfilter.cpp:281-340
- Status: Working

### VOC-HUD-020: HUD window categories individually toggleable
**Given** the four `hudShow*` keys **Then** notifications, OSD, dock(+tooltips), and applet popups can each be included/excluded from the HUD plane.
- Input source(s): config
- Config keys: `hudShowNotifications (true)`, `hudShowOsd (true)`, `hudShowDock (true)`, `hudShowAppletPopup (true)`
- Code: src/plugins/vr/qml/XrScene.qml:298-306, src/plugins/vr/windowmodelfilter.cpp:303-340
- Status: Working

### VOC-HUD-030: HUD windows are clickable
**Given** the ray hovers a HUD window **Then** the pick UV maps through the window's thumbnail texture frame into 2D window coordinates and the pointer warps there (clicks on the panel/start menu work); picks landing outside the frame (shadow region) are refused and fall through.
- Input source(s): mouse + head-pose
- Config keys: none
- Code: src/plugins/vr/qml/VrHudWindow.qml:96-139, src/plugins/vr/qml/VrHoverState.qml:36-45
- Status: Working

### VOC-HUD-040: Calibration grid plane
**Given** `hudEnabled` true **Then** a grid-patterned plane labelled "HUD PLANE" with the display dimensions renders on the HUD surface (curvature-conformal) for calibrating HUD placement.
- Input source(s): config
- Config keys: `hudEnabled (false)`
- Code: src/plugins/vr/qml/XrScene.qml:286-295, src/plugins/vr/qml/VrHudPlane.qml:34-105
- Status: Working

### VOC-HUD-050: Debug pick overlay
**Given** `debugDisplayEnabled` true **Then** a panel showing the current pick (hit object, UV, scene position, distance) renders in the configured corner of the HUD surface.
- Input source(s): config
- Config keys: `debugDisplayEnabled (false)`, `debugDisplayCorner (2 = bottom-left)`
- Code: src/plugins/vr/qml/VrHudPlane.qml:107-197
- Status: Working

### VOC-HUD-060: Ray-attached pick HUD (shortcut toggle)
**When** the "VR Hud" shortcut fires **Then** a separate debug panel (`XrayHud`, pick info) attached to the ray toggles on/off. Note this is distinct from `hudEnabled` (VOC-HUD-040) despite the name.
- Input source(s): shortcut (default Ctrl+Meta+H, see VOC-SHORTCUT-050)
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:187, src/plugins/vr/qml/XrScene.qml:38,327-335, src/plugins/vr/qml/XrayHud.qml:10-45
- Status: Working

### VOC-HUD-070: HUD transients lift toward the viewer
**Given** a HUD window has transient children (popup/menu over the dock, submenu over a menu) **Then** each child is placed one radial step (0.5 units) closer to the viewer per transient-chain level — on a concentric cylinder when curved — so it never z-fights or draws through its parent (chain depth ≤ 10, matching the filter's ancestor walk).
- Input source(s): n/a (window type routing)
- Config keys: `hudCurvature (0.0)`
- Code: src/plugins/vr/qml/VrHudWindow.qml:51-71, src/plugins/vr/qml/HudPlacementLogic.js
- Status: Working

---

## MENU — radial menu

### VOC-MENU-010: Right-click empty space opens the radial menu
**Given** the ray hovers nothing and nothing is grabbed **When** the right button is pressed and released over empty space **Then** a 5-button radial menu spawns 20 cm in front of the workspace plane (`distance − 20`) along the ray, facing the user, with an opening scale animation (180 ms); the press is consumed (no pass-through).
- Input source(s): mouse (right button)
- Config keys: `distance (100)`
- Code: src/plugins/vr/qml/Main.qml:109-113,134-138, src/plugins/vr/qml/XrScene.qml:117-130,340-360
- Status: Working

### VOC-MENU-020: Menu entries — Park Ray, Recenter, Grab All, Follow, Blend
**Given** the menu is open **Then** the five buttons act as: **Park Ray** disables the gaze ray (picking off) and closes the menu; **Recenter** triggers reset-view (VOC-WORLD-050) and closes; **Grab All** grabs the world (VOC-WORLD-040) and closes; **Follow** toggles follow mode (menu stays open, red border indicates on); **Blend** toggles passthrough/transparent background (stays open, red border indicates on).
- Input source(s): mouse (left click on segment)
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:363-398
- Status: Working — see note: Park Ray sets `pickRay.enabled = false` while a menu-lifetime Binding forces it true; the off state relies on Binding restore order at unload (Unverified edge).

### VOC-MENU-030: Center button closes the menu
**When** the center circle is clicked **Then** the menu plays its closing animation (90 ms) and unloads without any action.
- Input source(s): mouse
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:361, src/plugins/vr/qml/RadialMenu.qml:159-179
- Status: Working

### VOC-MENU-040: Escape closes the menu
**Given** the menu has keyboard focus (forced 50 ms after open) **When** Esc is released **Then** the menu closes.
- Input source(s): keyboard
- Config keys: none
- Code: src/plugins/vr/qml/RadialMenu.qml:19-47
- Status: Working

### VOC-MENU-050: Any key press closes the menu
**Given** the menu is open **When** any keyboard key is pressed (reaching the VR input layer) **Then** the menu closes before the key is further processed.
- Input source(s): keyboard
- Config keys: none
- Code: src/plugins/vr/qml/Main.qml:42-43, src/plugins/vr/qml/XrScene.qml:132-138
- Status: Working

### VOC-MENU-060: Right-click over a window closes the menu and falls through
**Given** the menu is open **When** the right button goes down over a window **Then** the menu closes and the click is delivered to the window normally.
- Input source(s): mouse
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:126-129, src/plugins/vr/qml/Main.qml:109-116
- Status: Working

### VOC-MENU-070: Menu forces the ray on while open
**Given** the gaze ray was disabled (parked) **When** the menu is open **Then** picking is force-enabled so the menu itself is clickable; the prior enablement is restored when the menu unloads.
- Input source(s): n/a (state interaction)
- Config keys: none
- Code: src/plugins/vr/qml/XrScene.qml:350-354
- Status: Working

---

## SHORTCUT — global shortcuts

All VR shortcuts are registered with KGlobalAccel using `setDefaultShortcut(default)` followed by
`setShortcut(action, {})` — i.e. only the *default* binding is declared; the *active* binding is
whatever KGlobalAccel has saved (defaults apply on first registration under standard autoloading,
but this differs from KWin's usual pattern of passing the sequence to both calls). Marked
Unverified where the key sequence's out-of-box availability matters.

### VOC-SHORTCUT-010: Activate VR Mode — Ctrl+Meta+J (default)
**When** triggered **Then** VR mode toggles (enter if off, exit if on). Registered at plugin load, works outside VR.
- Input source(s): shortcut
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:60-65,286-290
- Status: Working

### VOC-SHORTCUT-020: Realign VR Window — Ctrl+Meta+W (default)
**Then** the hovered grab handle turns to face the camera (VOC-WORLD-070).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:26-29, src/plugins/vr/qml/Main.qml:184
- Status: Working

### VOC-SHORTCUT-030: Grab Window — Ctrl+Meta+E (default)
**Then** grab/release the hovered window (VOC-GRAB-010).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:31-34, src/plugins/vr/qml/Main.qml:185
- Status: Working

### VOC-SHORTCUT-040: Grab All Windows — Shift+Meta+E (default)
**Then** grab/release the whole workspace (VOC-WORLD-040).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:36-39, src/plugins/vr/qml/Main.qml:186
- Status: Working

### VOC-SHORTCUT-050: VR Hud — Ctrl+Meta+H (default)
**Then** toggle the ray-attached pick HUD (VOC-HUD-060).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:41-44, src/plugins/vr/qml/Main.qml:187
- Status: Working

### VOC-SHORTCUT-060: VR Test Action 1 — Ctrl+Meta+K (default)
**Then** `test1` toggles, each toggle calling `KwinVrHelpers.activateOutput(virtualOutput, scale)` — a developer action that re-activates the virtual screen output.
- Code: src/plugins/vr/kwinvrshortcuts.cpp:46-49, src/plugins/vr/qml/XrScene.qml:48-51
- Status: Unverified — developer/test hook, effect on user session not characterized

### VOC-SHORTCUT-070: VR Test Action 2 — Ctrl+Meta+L (default)
**Then** `xrView.die()` is called — which is an **empty function**. No observable effect.
- Code: src/plugins/vr/kwinvrshortcuts.cpp:51-54, src/plugins/vr/qml/XrScene.qml:53
- Status: Buggy — intentionally(?) a no-op stub; either implement or remove.

### VOC-SHORTCUT-080: Disable VR Ray — Ctrl+Meta+I (default)
**Then** the gaze ray's enabled state toggles: disabling stops picking updates entirely (hover, warping, cursor binding freeze with stale state until re-enabled).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:56-59, src/plugins/vr/qml/Main.qml:190, src/plugins/vr/qml/VrPicking.qml:67-73
- Status: Working

### VOC-SHORTCUT-090: Toggle VR Cursor — Ctrl+Meta+C (default)
**Then** the 3D cursor sprite's visibility toggles (picking unaffected).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:61-64, src/plugins/vr/qml/Main.qml:191, src/plugins/vr/qml/VrCursorManager.qml:20,45-69
- Status: Working

### VOC-SHORTCUT-100: Reset View — Ctrl+Meta+T (default)
**Then** the workspace recenters in front of the user (VOC-WORLD-050).
- Code: src/plugins/vr/kwinvrshortcuts.cpp:66-69, src/plugins/vr/qml/Main.qml:192
- Status: Working

---

## INPUT — bindable VR-controller / key remapping

### VOC-INPUT-010: Controller buttons bindable to mouse buttons or keys
**Given** an InputMapping entry (e.g. `rightTriggerTouched = MouseLeft` or a key-sequence string) **When** the bound XR action (Button1/2, Menu, System, Trigger/Thumbstick/Trackpad/Thumbrest touch, finger pinches, hand-tracking menu press — per controller) changes pressed state **Then** the mapped mouse button (`MouseLeft/Middle/Right/Back/Forward`) or key code is pressed/released on the VR input device. All bindings default empty (inactive).
- Input source(s): gamepad/VR controller
- Config keys: `left*/right*` String entries in group `InputMapping` (all default empty)
- Code: src/plugins/vr/qml/VrInputBindings.qml:22-106, src/plugins/vr/kwinvr.kcfg:347-531
- Status: Unverified — requires controller hardware

### VOC-INPUT-020: Analog squeeze/trigger with threshold
**Given** `leftSqueezePressed`/`rightTriggerPressed` etc. bound and threshold (`*SqueezeValue`/`*TriggerValue`, default 0.5) > 0 **When** the analog value crosses the threshold **Then** the binding fires pressed/released like a button.
- Input source(s): gamepad/VR controller
- Config keys: `left/rightSqueezePressed`, `left/rightTriggerPressed` (empty), `left/rightSqueezeValue (0.5)`, `left/rightTriggerValue (0.5)`
- Code: src/plugins/vr/qml/VrInputBindings.qml:45-51,108-125
- Status: Unverified — requires controller hardware

### VOC-INPUT-030: Thumbstick scroll
**Given** a thumbstick axis scale ≠ 0 **When** the stick deflects beyond 0.05 **Then** continuous scroll is injected each frame: `value × scale × frameTime × 500` (Y inverted vertical, X horizontal).
- Input source(s): gamepad/VR controller
- Config keys: `left/rightThumbstickX (0.0)`, `left/rightThumbstickY (0.0)` — 0 disables
- Code: src/plugins/vr/qml/VrInputBindings.qml:53-57,127-149
- Status: Unverified — requires controller hardware

### VOC-INPUT-040: Keyboard keys remapped to mouse clicks
**Given** keys listed in `leftClickBindings`/`middleClickBindings`/`rightClickBindings` **When** such a key is pressed/released **Then** it is consumed and converted to the corresponding mouse button press/release on the VR device (so a keyboard-only user can click).
- Input source(s): keyboard
- Config keys: `leftClickBindings ()`, `middleClickBindings ()`, `rightClickBindings ()`
- Code: src/plugins/vr/kwinvrinputremap.cpp:27-47,117-144, src/plugins/vr/qml/Main.qml:29-31
- Status: Working

### VOC-INPUT-050: VR input event routing
**Given** VR active **Then** keyboard, mouse-button, wheel, and pinch events are intercepted at the `Effects` filter slot and delivered to the VR interaction layer (Main.qml MouseArea) first; only unaccepted events continue to normal KWin dispatch. Button releases are always consumed if the matching press was.
- Input source(s): keyboard/mouse/touchpad
- Config keys: none
- Code: src/plugins/vr/kwinvrinputfilter.cpp:38-159, src/plugins/vr/qml/Main.qml:23-27,39-154
- Status: Working — caveat: the `onWheel` handler never sets `event.accepted = false`, so **all** wheel events appear to be consumed even when nothing is grabbed (Unverified whether app scrolling via physical wheel still works through another path).

---

## LIFECYCLE — VR enter/exit, auto-lease, autostart, DBus

### VOC-LIFECYCLE-010: DBus surface org.kde.kwinvr
**Given** KWin running with the plugin **Then** service `org.kde.kwinvr`, object `/KwinVr`, exposes: property `vrActive` (read/write — writing toggles VR), slots `leasableOutputs()`, `setOutputLeasable(name, leasable)`, `refreshLeases()`, signals `vrActiveChanged`, `leasableOutputsChanged`. Registration failure is non-fatal (shortcut still works).
- Input source(s): dbus
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:523-538, src/plugins/vr/kwinvr.h:24-44
- Status: Working

### VOC-LIFECYCLE-020: VR entry sequence
**When** `vrActive` is set true (shortcut/DBus/autostart) **Then**, in order: optional OpenXR loader init from `openXrRuntimeJson`; ensure Monado is running (VOC-LIFECYCLE-030); "Starting VR mode / Standby" persistent notification; QML engine created (`m_active = true`); if `xrTestEnabled` an isolated OpenXR session smoke-test runs first and only on success does the real scene load; pointer position limiter neutralized, VR popup bounds resolver installed, `workspace()->setVrMode(true)`, dmabuf format filter on, then `Main.qml` loads.
- Input source(s): shortcut / dbus / automatic
- Config keys: `xrTestEnabled (true)`, `openXrRuntimeJson ("")`
- Code: src/plugins/vr/kwinvr.cpp:218-348
- Status: Working

### VOC-LIFECYCLE-030: Monado auto-start with socket liveness poll
**Given** the Monado IPC socket (`$XDG_RUNTIME_DIR/monado_comp_ipc`) is not **live** (no listener accepts a connection — a stale file left by a crashed Monado does not count, and is logged but never deleted: under systemd socket activation the connect itself starts the service) at activation **Then** `systemctl --user start monado.service` is spawned and the socket is connect-polled every 500 ms; activation proceeds when a connection is accepted, or fails with a notification after 15 s.
- Input source(s): automatic
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:171-235, src/plugins/vr/kwinvrhelpers.cpp (`isUnixSocketAlive`)
- Status: Working (liveness check pinned by `kwinvr-testHelpers`; full path needs hardware)

### VOC-LIFECYCLE-040: VR exit restores the 2D session
**When** VR deactivates (toggle off, XR failure, session end) **Then** the QML engine is destroyed and on destruction: `setVrMode(false)`, every window's `vr` flag cleared (all windows return to screens), dmabuf filter off, pointer limiter and popup resolver removed, `vrActive` notifies false. The virtual output is removed by its handle's destructor.
- Input source(s): shortcut / dbus / error
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:225-240,350-358, src/plugins/vr/kwinvirtualscreenhandle.cpp:21-28
- Status: Working

### VOC-LIFECYCLE-050: XR failure → notification + clean stop
**Given** XR initialization fails or the session ends **Then** a "Failed to Activate VR mode" notification with the error text is shown and VR tears down (VOC-LIFECYCLE-040).
- Input source(s): automatic (runtime error)
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:67-85, src/plugins/vr/qml/XrScene.qml:20-21
- Status: Working

### VOC-LIFECYCLE-060: Auto-lease configured outputs (SBS gate)
**Given** `autoLeaseOutputs` non-empty **When** outputs are (re)enumerated, once per session **Then** each named output that supports leasing, is not non-desktop, **and is in SBS mode (mode width ≥ 3840)** is marked leasable; outputs not in SBS mode are skipped. After committing, leases are refreshed (VOC-LIFECYCLE-080).
- Input source(s): automatic (output hotplug)
- Config keys: `autoLeaseOutputs ()`
- Code: src/plugins/vr/kwinvr.cpp:437-494
- Status: Working

### VOC-LIFECYCLE-070: Autostart VR after lease grant
**Given** `autostartVr` true and auto-lease committed **When** any configured output becomes leased/lease-pending **Then** VR mode starts automatically after a 3 s settling delay.
- Input source(s): automatic
- Config keys: `autostartVr (false)`, `autoLeaseOutputs ()`
- Code: src/plugins/vr/kwinvr.cpp:487-521
- Status: Working

### VOC-LIFECYCLE-080: Refresh leases
**When** `refreshLeases()` is invoked (DBus/KCM, or after auto-lease) **Then** `monado.service` is restarted and every leasable-but-unleased output is toggled leasable off→on to force a fresh DRM lease offer.
- Input source(s): dbus / automatic
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:414-435
- Status: Working

### VOC-LIFECYCLE-090: Config hot-reload
**Given** VR running **When** `~/.config/kwinvr` changes (e.g. from the KCM) **Then** the config wrapper reloads and bound QML properties (distances, HUD params, sensitivities, bindings…) update live.
- Input source(s): config file change
- Config keys: all
- Code: src/plugins/vr/kwinvr.cpp:42-44
- Status: Working

### VOC-LIFECYCLE-100: NVIDIA multiview guard
**Given** `multiview` true and `/sys/module/nvidia` exists (proprietary driver) **Then** multiview is forced off (GLSL 140 vs GL_OVR_multiview2 incompatibility would yield a black screen) with a warning log.
- Input source(s): automatic
- Config keys: `multiview (false)`, `threadedRendering (false)`, `overlayPlacement (20)`
- Code: src/plugins/vr/kwinvr.cpp:314-325
- Status: Working

### VOC-LIFECYCLE-110: Screen-lock hides window content in VR
**Given** the session locks while VR is active **Then** all window planes except lock-screen, lock-screen-overlay, and input-method surfaces become invisible (HUD and scene alike).
- Input source(s): automatic (lock)
- Config keys: none
- Code: src/plugins/vr/qml/KwinTransientWindow.qml:13, src/plugins/vr/qml/VrHudWindow.qml:76-78
- Status: Working

### VOC-LIFECYCLE-120: Passthrough blend
**Given** `blend` true (default) **Then** the scene background is transparent with XR passthrough enabled (real surroundings visible); false gives an opaque skyblue void. Toggleable live from the radial menu (VOC-MENU-020 "Blend").
- Input source(s): config / radial menu
- Config keys: `blend (true)`, `depthPrePassEnabled (false)`, `depthTestEnabled (true)`
- Code: src/plugins/vr/qml/XrScene.qml:221-227,389-397
- Status: Working

---

## OUTPUT — virtual screen and leasable outputs

### VOC-OUTPUT-010: Virtual screen created from template on VR entry
**Given** VR mode starts **Then** a virtual output named from template (`Virtual-T`, description "Virtual Screen") is created with pixel size `width×scale` by `height×scale`, the given scale, and `refreshrate` Hz (passed as mHz), enabled with a preferred custom mode. Windows live on this screen by default while "on screen" in VR.
- Input source(s): automatic
- Config keys: `width (1440)`, `height (900)`, `scale (1)`, `refreshrate (60)`
- Code: src/plugins/vr/qml/XrScene.qml:56-65, src/plugins/vr/kwinvirtualscreenhandle.cpp:50-93, src/plugins/vr/kwinvrhelpers.h:69
- Status: Working

### VOC-OUTPUT-020: Virtual screen recreated on geometry change
**Given** VR running **When** width/height/scale/refreshrate config changes **Then** the virtual output is destroyed and recreated (size/name change) or just reconfigured (refresh/scale only) live.
- Input source(s): config
- Config keys: as VOC-OUTPUT-010
- Code: src/plugins/vr/kwinvirtualscreenhandle.cpp:50-93
- Status: Working

### VOC-OUTPUT-030: Virtual screen removed on VR exit
**When** the VR scene is torn down **Then** the virtual output is removed from the backend (windows on it migrate per KWin's output-removal rules).
- Input source(s): automatic
- Config keys: none
- Code: src/plugins/vr/kwinvirtualscreenhandle.cpp:21-28
- Status: Working

### VOC-OUTPUT-040: Leasable output enumeration
**When** `leasableOutputs()` is queried (DBus/KCM) **Then** every backend output with the Leasing capability that is not non-desktop is listed with name, manufacturer, model, leasable flag, and leased/lease-pending state; the list change signal fires on output queries and lease state changes.
- Input source(s): dbus
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:381-398,51-52
- Status: Working

### VOC-OUTPUT-050: Set output leasable
**When** `setOutputLeasable(name, bool)` is invoked **Then** the named output's leasable flag is applied through an output configuration transaction; returns success/failure.
- Input source(s): dbus
- Config keys: none
- Code: src/plugins/vr/kwinvr.cpp:400-412
- Status: Working

---

## FLAT — flat-monitor mode (M2, no HMD)

### VOC-FLAT-010: Flat displayMode enters the workspace without HMD or XR runtime
**Given** `displayMode=Flat` **When** VR is activated (DBus `vrActive=true`, shortcut, or autostart) **Then** the 3D workspace starts directly — no OpenXR loader check, no Monado autostart, no DRM lease — by loading `MainFlat` instead of `Main`.
- Input source(s): dbus / shortcut / config
- Config keys: `displayMode (Auto)` — values `Auto`, `Xr`, `Flat`
- Code: src/plugins/vr/kwinvr.cpp:252-267,363, src/plugins/vr/kwinvr.kcfg:220
- Status: Working (verified headless 2026-06-09)

### VOC-FLAT-020: Flat scene renders the identical workspace through a perspective camera
**Given** flat mode active **Then** the same `VrWorkspaceScene` (virtual screen, pseudomirrors, ray, snap manager, radial menu, follow mode) renders into a fullscreen `View3D` with a `PerspectiveCamera` (`fieldOfView = flatFov`) against a sky-blue background.
- Input source(s): automatic
- Config keys: `flatFov (90.0)`
- Code: src/plugins/vr/qml/FlatScene.qml:21-69, src/plugins/vr/qml/MainFlat.qml:19-62, src/plugins/vr/qml/VrWorkspaceScene.qml
- Status: Working

### VOC-FLAT-030: Middle-button drag turns the flat "head"
**Given** flat mode active **When** the user drags with the middle mouse button **Then** the camera rig yaws by `-dx×flatLookSensitivity` and pitches by `-dy×flatLookSensitivity` degrees, pitch clamped to ±89°, so gaze-coupled behaviors (follow mode, gaze reclaim, head scroll) keep working with the rig as the head stand-in.
- Input source(s): mouse
- Config keys: `flatLookSensitivity (0.15 °/px)`
- Code: src/plugins/vr/qml/FlatScene.qml:37-59, src/plugins/vr/qml/MainFlat.qml:52-61, src/plugins/vr/qml/VrInputSurface.qml (middleDragLook)
- Status: Working

### VOC-FLAT-040: Interaction grammar is shared, not forked
**Given** flat mode active **Then** every non-head-pose vocabulary behavior (GRAB, WORLD, RESIZE, SNAP, MENU, GAZE pointer-offset…) runs through the same `VrInputSurface` + `VrWorkspaceScene` code paths as XR mode — there is no flat-specific reimplementation to drift out of sync.
- Input source(s): all
- Config keys: as per the referenced behaviors
- Code: src/plugins/vr/qml/VrInputSurface.qml, src/plugins/vr/qml/VrWorkspaceScene.qml
- Status: Working — interaction end-states verified on the flat substrate by kwinvr-testFlatReplay (M2 slice 3)

### VOC-FLAT-050: Passthrough blend is unavailable flat
**Given** flat mode active **Then** `blendSupported` is false and the blend toggle is inert (passthrough is an HMD concept).
- Input source(s): n/a
- Config keys: none
- Code: src/plugins/vr/qml/FlatScene.qml:68
- Status: Working

### VOC-FLAT-060: Auto mode currently resolves to the XR path
**Given** `displayMode=Auto` (the default) **Then** activation behaves exactly as `Xr` — HMD-presence detection to auto-fall-back to flat is **not yet implemented** (planned with M4 runtime profiles).
- Input source(s): config
- Config keys: `displayMode (Auto)`
- Code: src/plugins/vr/kwinvr.cpp:252-257
- Status: Working as documented (auto-detection TBD)

---

## Appendix A — Status / coverage matrix

| VOC-ID | Status | Test coverage |
|---|---|---|
| VOC-GAZE-010 | Working | none — smoke only |
| VOC-GAZE-020 | Working | none — smoke only |
| VOC-GAZE-030 | Working | none — smoke only |
| VOC-GAZE-040 | Working | none — smoke only |
| VOC-GAZE-050 | Working | none — smoke only |
| VOC-GAZE-060 | Working | none — smoke only |
| VOC-GAZE-070 | Working | none — smoke only |
| VOC-GAZE-080 | Working | none — smoke only |
| VOC-GAZE-090 | Working | none — smoke only |
| VOC-GAZE-100 | Working | none — smoke only |
| VOC-GAZE-110 | Working | none — smoke only |
| VOC-GAZE-120 | Working | none — smoke only |
| VOC-GAZE-130 | Working | none — smoke only |
| VOC-GRAB-010 | Working | none — smoke only |
| VOC-GRAB-020 | Working | none — smoke only |
| VOC-GRAB-030 | Working | none — smoke only |
| VOC-GRAB-040 | Working | none — smoke only |
| VOC-GRAB-050 | Working | kwinvr-testFlatReplay (scroll changes world-grab depth; flat substrate) |
| VOC-GRAB-060 | Working | none — smoke only |
| VOC-GRAB-070 | Working | none — smoke only |
| VOC-GRAB-080 | Working | none — smoke only |
| VOC-WORLD-010 | Working | none — smoke only |
| VOC-WORLD-020 | Working | none — smoke only |
| VOC-WORLD-030 | Working | none — smoke only |
| VOC-WORLD-040 | Working | kwinvr-testFlatReplay (grab(true)/release end-state; flat substrate) |
| VOC-WORLD-050 | Working | kwinvr-testFlatReplay (executes without error) — recenter end-state assert pending |
| VOC-WORLD-060 | Working | none — smoke only |
| VOC-WORLD-070 | Working | none — smoke only |
| VOC-RESIZE-010 | Working | none — smoke only |
| VOC-RESIZE-020 | Working | none — smoke only |
| VOC-RESIZE-030 | Unverified | none — smoke only |
| VOC-SNAP-010 | Working | kwinvr-testQmlLogic (edge-band UV decision table) |
| VOC-SNAP-020 | Working | kwinvr-testQmlLogic (center zone → Stack, corner precedence) |
| VOC-SNAP-030 | Working | kwinvr-testQmlLogic (landing-pose math) — ghost rendering smoke only |
| VOC-SNAP-040 | WIP | none — smoke only |
| VOC-SNAP-050 | WIP | none — smoke only |
| VOC-SNAP-060 | Working | kwinvr-testFlatSnapReplay (commit resizes member to root frame size, stackedOnto/stackIndex set; flat substrate) |
| VOC-SNAP-070 | WIP | none — smoke only |
| VOC-SNAP-080 | Unverified | none — smoke only |
| VOC-SNAP-090 | Unverified | none — smoke only |
| VOC-SNAP-100 | Unverified | none — smoke only |
| VOC-SNAP-110 | Unverified | none — smoke only |
| VOC-SNAP-120 | WIP | none — smoke only |
| VOC-SNAP-130 | Unverified | none — smoke only |
| VOC-SNAP-140 | Buggy | none — smoke only |
| VOC-SNAP-150 | Working | kwinvr-testFlatSnapReplay (root resize propagates, member self-resize snaps back, cascade pose survives re-placement) |
| VOC-MIRROR-010 | Working | none — smoke only |
| VOC-MIRROR-020 | Working | none — smoke only |
| VOC-MIRROR-030 | Working | none — smoke only |
| VOC-MIRROR-040 | Working | none — smoke only |
| VOC-MIRROR-050 | Working | none — smoke only |
| VOC-MIRROR-060 | Working | kwinvr-testFlatFloatReplay (Virtual-T mirror hidden at start) |
| VOC-MIRROR-065 | Working | none — smoke only |
| VOC-MIRROR-070 | Working | none — smoke only |
| VOC-MIRROR-080 | Working | kwinvr-testFlatFloatReplay (promotion on detach, birth-on-hidden, one-way) |
| VOC-PLACE-010 | Working | kwinvr-testSpaceAllocator3D (front-hemisphere cap, slot scan) |
| VOC-PLACE-020 | Working | none — smoke only |
| VOC-PLACE-030 | Working | kwinvr-testSpaceAllocator3D (fallback on hemisphere exhaustion) |
| VOC-PLACE-040 | Working | none — smoke only |
| VOC-FOLLOW-010 | Working | none — smoke only |
| VOC-FOLLOW-020 | Working | none — smoke only |
| VOC-FOLLOW-030 | Working | none — smoke only |
| VOC-FOLLOW-040 | Working | none — smoke only |
| VOC-FOLLOW-050 | Working | none — smoke only |
| VOC-FOLLOW-060 | Working | none — smoke only |
| VOC-HUD-010 | Working | kwinvr-testFlatHudReplay (layer-shell dock + xdg-popup admitted to / leave the HUD; flat substrate) + kwinvr-testQmlLogic (cylinder placement math) |
| VOC-HUD-020 | Working | none — smoke only |
| VOC-HUD-030 | Working | none — smoke only |
| VOC-HUD-040 | Working | none — smoke only |
| VOC-HUD-050 | Working | none — smoke only |
| VOC-HUD-060 | Working | none — smoke only |
| VOC-HUD-070 | Working | kwinvr-testQmlLogic (lift ladder, radial-lift geometry, flat/curved) + kwinvr-testFlatHudReplay (live popup z > dock z) |
| VOC-MENU-010 | Working | none — smoke only |
| VOC-MENU-020 | Working | none — smoke only |
| VOC-MENU-030 | Working | none — smoke only |
| VOC-MENU-040 | Working | none — smoke only |
| VOC-MENU-050 | Working | none — smoke only |
| VOC-MENU-060 | Working | none — smoke only |
| VOC-MENU-070 | Working | none — smoke only |
| VOC-SHORTCUT-010 | Working | none — smoke only |
| VOC-SHORTCUT-020 | Working | none — smoke only |
| VOC-SHORTCUT-030 | Working | none — smoke only |
| VOC-SHORTCUT-040 | Working | none — smoke only |
| VOC-SHORTCUT-050 | Working | none — smoke only |
| VOC-SHORTCUT-060 | Unverified | none — smoke only |
| VOC-SHORTCUT-070 | Buggy | none — smoke only |
| VOC-SHORTCUT-080 | Working | none — smoke only |
| VOC-SHORTCUT-090 | Working | none — smoke only |
| VOC-SHORTCUT-100 | Working | none — smoke only |
| VOC-INPUT-010 | Unverified | none — smoke only |
| VOC-INPUT-020 | Unverified | none — smoke only |
| VOC-INPUT-030 | Unverified | none — smoke only |
| VOC-INPUT-040 | Working | none — smoke only |
| VOC-INPUT-050 | Working | none — smoke only |
| VOC-LIFECYCLE-010 | Working | kwinvr-testFlatBoot (service appears, vrActive writable over DBus) |
| VOC-LIFECYCLE-020 | Working | none — smoke only |
| VOC-LIFECYCLE-030 | Working | none — smoke only |
| VOC-LIFECYCLE-040 | Working | none — smoke only |
| VOC-LIFECYCLE-050 | Working | none — smoke only |
| VOC-LIFECYCLE-060 | Working | none — smoke only |
| VOC-LIFECYCLE-070 | Working | none — smoke only |
| VOC-LIFECYCLE-080 | Working | none — smoke only |
| VOC-LIFECYCLE-090 | Working | none — smoke only |
| VOC-LIFECYCLE-100 | Working | none — smoke only |
| VOC-LIFECYCLE-110 | Working | none — smoke only |
| VOC-LIFECYCLE-120 | Working | none — smoke only |
| VOC-OUTPUT-010 | Working | none — smoke only |
| VOC-OUTPUT-020 | Working | none — smoke only |
| VOC-OUTPUT-030 | Working | none — smoke only |
| VOC-OUTPUT-040 | Working | none — smoke only |
| VOC-OUTPUT-050 | Working | none — smoke only |
| VOC-FLAT-010 | Working | **kwinvr-testFlatBoot** (headless boot, vrActive, 0 QML errors) |
| VOC-FLAT-020 | Working | kwinvr-testFlatBoot (renders non-black frame at real geometry) — golden diff pending |
| VOC-FLAT-030 | Working | kwinvr-testFlatReplay (lookBy yaw/pitch sensitivity + ±89° clamp) |
| VOC-FLAT-040 | Working | kwinvr-testFlatReplay (grab/scroll/release/reset + real Wayland client placed, via shared seam) |
| VOC-FLAT-050 | Working | none — smoke only |
| VOC-FLAT-060 | Working as documented | none |

## Appendix B — Known oddities discovered during enumeration

1. **Wheel black-hole risk**: `Main.qml` `onWheel` never sets `event.accepted = false`, so the VR input filter consumes every physical wheel event even when nothing is grabbed (VOC-INPUT-050 caveat).
2. **Dead signal**: `stackFocusRequested` has a handler but no emitter (VOC-SNAP-140).
3. **Shortcut registration** uses `setShortcut(action, {})` (empty active sequence) — defaults are declared but actual activation depends on KGlobalAccel autoloading state.
4. **`VrOsdWindows.qml` is orphaned** — exists with an `OsdWindowFilter` but is never instantiated; OSD windows are handled by the HUD path instead.
5. **WIP doc drift**: `doc/DOCK_AND_STACK_WIP.md` describes quad-overlap detection and a cm→m `/100` conversion; the current `WindowSnapManager.qml` uses UV bands and raw `zSurfaceMarginTop`. The WIP doc remains ground truth for *status* (commit/adhesion unproven), not for *mechanism*.
6. **Test Action 2** is bound to an empty function (VOC-SHORTCUT-070).
