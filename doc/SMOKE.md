# Manual Smoke Checklist

10-minute pass covering VR behaviors CI cannot exercise yet (golden-image and
input-replay tests arrive with flat-monitor mode in M2; XR-session tests in M4).
Run before merging any VR-behavior PR and note "smoke: pass / item N failed" in
the PR description. Items reference `doc/VOCABULARY.md` IDs — read the VOC entry
for exact expected behavior.

Hardware: the current daily-driver rig (Xreal Air + Monado). Start from a cold
session unless an item says otherwise.

## 1. Lifecycle (≈2 min)
- [ ] S1 — Glasses plugged in pre-login: session reaches the 3D workspace without manual DBus calls (VOC-LIFECYCLE: auto-lease + autostart)
- [ ] S2 — `qdbus org.kde.kwinvr` exit/re-enter VR twice: no freeze, no black screen, windows return to their layout
- [ ] S3 — Hot-unplug glasses while VR active: compositor survives, desktop usable on remaining outputs

## 2. Gaze + cursor (≈1 min)
- [ ] S4 — Head movement steers the cursor; small offsets via mouse work (VOC-GAZE: pointer offset)
- [ ] S5 — Turn head past threshold: cursor reclaims to center (gaze reclaim)

## 3. Window grab + depth (≈2 min)
- [ ] S6 — Grab a window (Ctrl+Meta+E), move it, release: it stays where released (VOC-GRAB-010)
- [ ] S7 — While grabbed, scroll wheel pushes/pulls window depth
- [ ] S8 — Left-press empty space + drag: world-grab moves the whole scene; click without moving latches (VOC-WORLD)
- [ ] S9 — Shift/Ctrl+wheel on a hovered window resizes it (VOC-RESIZE)

## 4. Snap / dock / stack (≈2 min) — WIP area, see VOC-SNAP statuses
- [ ] S10 — Drag window near another: telegraph appears on edge bands
- [ ] S11 — Release on telegraph: window docks (KNOWN-WIP if commit fails — record exact behavior)
- [ ] S12 — Click a stacked window without dragging: it promotes to stack top

## 5. Pseudomirrors (≈1 min)
- [ ] S13 — Physical-monitor mirror visible at configured distance; windows on it adhere when it's moved
- [ ] S14 — Drag a window off the mirror past the barrier: it detaches to free-float; drag back on: it lands on the monitor

## 6. Placement + follow (≈1 min)
- [ ] S15 — Open 3 new windows: each auto-places without occluding the others (VOC-PLACE)
- [ ] S16 — With follow enabled, walk view past the follow FOV: windows catch up smoothly (VOC-FOLLOW)

## 7. Menu + HUD (≈1 min)
- [ ] S17 — Right-click empty space: radial menu opens, entries act, Esc/click-away closes (VOC-MENU)
- [ ] S18 — HUD toggle shortcut shows/hides HUD plane; notifications/OSD render on it (VOC-HUD)

## Recording results
Append a line to the PR description:
`smoke: pass (S1–S18) on <hardware>, <date>` or `smoke: S11 failed — <one line>`.
