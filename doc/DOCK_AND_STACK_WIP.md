# Natural-Drag Dock + Stack — WIP State (2026-04-22)

Working doc for issue #14 implementation. Read this first when resuming.

## Current branch + baseline

- Branch: `feat/window_dock` off `6.6.3_vr_main` at `a7c3f2face` (pre-work-surfaces).
- `6.6.3_vr_bake` is **archived** — rolled back after WS-era QML stress hard-froze VR mode entry. Tag `archive/6.6.3_vr_bake_pre_rollback` marks last bake commit `acba70807b`.
- Pre-WS baseline confirmed stable: VR autostarts, fast, no freeze.

## Locked design (issue #14)

| Item | Decision |
|------|----------|
| Detection | Per-frame quad overlap during VR-window drag |
| Threshold | ≥3 combined participating quads (rejects diagonal corners) |
| Quad pattern | Same-side ↔ same-side = STACK; opposite-side ↔ opposite-side = SNAP that direction |
| Multi-target | Closest center wins |
| Snap-slot collision | Falls out naturally — overlap shifts to occupying neighbor → its quad pattern dictates action |
| Esc | Cancels snap intent only, drag continues |
| Detach | Any drag of a grouped member auto-detaches |
| Group move | Shift+drag moves whole transitive group |
| Snap resize | Dragged matches target HEIGHT (h-snap) or WIDTH (v-snap), both edges align |
| Stack resize | Dragged matches target full SIZE |
| Stack offset | Each member offset by uniform vector (matches pseudomirror z-spacing convention) |
| Stack snap target | Topmost in stack — new window becomes new top, prev top falls into peek slot |
| Original size | `preSnapGeom` snapshot on first snap; restored on detach |
| Group split | A-B-C-D-E with C removed → A-B / C / D-E (no auto-merge) |
| Group orient | Snap groups face user as one unit; lock at snap moment, not live |
| Telegraph | Solid translucent rectangle in landing pose (curvature-inclusive later) |
| Mixing | Snaps + stacks combine freely |

## Implementation actually done

### Files modified
- `src/plugins/vr/qml/WindowSnapManager.qml` — NEW. ~310 lines. Singleton-like QtObject mounted in XrScene.
- `src/plugins/vr/qml/XrScene.qml` — Mount `WindowSnapManager` after `VrFocusControl`. Added telegraph `Model` as sibling to repeaters under `allWindowsGrabHandle`.
- `src/plugins/vr/CMakeLists.txt` — Added `qml/WindowSnapManager.qml` to QML_FILES.

### Step 1: quad scan + log (DONE)
- Per-frame `_scan()` triggered by `xray.onSceneTransformChanged` while `xray.grabbedObject` is a VR-floating window.
- `_evaluatePair(dragged, target)` — projects dragged corners into target local 2D, computes overlap rect, uses centroid bias to classify (replaces vote-tally because VR drag motion never hits clean half-shifts).
- Stack zone: |xBias| AND |yBias| < 0.4. Otherwise dominant-axis bias picks snap direction.
- Plane-distance gate: rejects candidates whose plane is >1m from dragged center.
- Overlap area gate: <5% of min(target,dragged) area = no-op (diagonal corner rejection).
- Logs: `Snap intent: <Action> → <wmClass>` on intent change. Confirmed firing in journal at `Apr 22 09:51` series.

### Step 2: telegraph rect (DONE, working)
- `Model { source: "#Rectangle" }` in scene, parented under `allWindowsGrabHandle`.
- `#Rectangle` mesh is **100×100 units**. Scale = (w/100, h/100, 1) to get final size W × H.
- `landingLocalOffset` + `landingSize` computed in `_computeLanding()` (target-local coords).
- Position = `allWindowsGrabHandle.mapPositionFromScene(target.mapPositionToScene(landingLocalOffset))`. Rotation = `target.rotation`.
- Material: `DefaultMaterial` translucent cyan, `cullMode: NoCulling`, `depthBias: -100`, `depthDrawMode: OpaqueOnlyDepthDraw`.
- User confirmed: telegraphs "look pretty ok".

### Step 3: commit on release + Z-stick (PARTIAL — NOT WORKING)
- `_grabWatcher` Connections fires on `xray.onGrabbedObjectChanged`. When transitioning to null, if `_lastDragged && currentTarget && currentAction !== None`, calls `_commitSnap`.
- `_commitSnap` does: capture `preSnapGeom` (first snap), `KwinVrHelpers.windowResize(client, dw_px, dh_px)`, `setNodePositionFromScene`, `setNodeRotationFromScene`.
- Z forward offset in commit: `KWinVRConfig.zSurfaceMarginTop / 100.0` (kcfg stores in cm, scene needs metres). Default cm value is 1.0 → 0.01m forward.
- Z-stick during drag: only `localCenter.z < zFwd` triggers; clamps z while preserving lateral. **User confirms still not working** — windows don't lay on target plane like pseudomirrors do.

## Current symptoms

User's last test (latest build):
1. **Telegraphs slightly improved** (presumably side snaps now firing, not flickering — but unconfirmed).
2. **Window does not resize or move on release.** Commit isn't visibly happening.
3. **Windows don't assume target's z orientation during drag** — no pseudomirror-style surface adhesion. The Z-only depth clamp I added isn't producing visible collision.
4. **Logs not yet captured** for this build — user hasn't tailed `journalctl --user -f | grep kwinvr` during a test.

## Hypotheses for "commit doesn't move window"

Need to verify with logs, do not guess further before then:

- **H1: `_grabWatcher` doesn't fire** — wiring bug. Check if release log appears at all.
- **H2: Conditions fail at release moment** — `currentTarget` cleared by a final scan between user's input release and `onGrabbedObjectChanged`. `Snap release:` log will show `target=null`.
- **H3: `_commitSnap` runs but `setNodePositionFromScene` is overridden** — by `KwinVrHelpers.windowResize` async re-render, by KwinApplicationWindow state machine, or by Xray applyRelativePose still firing somehow.
- **H4: Position is set correctly but window's frameGeometry binding (`itemSize`) recomputes position elsewhere** — `centerOffset` is only in screen state, but worth verifying.
- **H5: `windowResize` delta math wrong** — `(landW * target.ppu - dg.width)` could be way off if ppu mismatch.

## Hypotheses for "no surface adhesion"

- **H6: Z-clamp guard `if (localCenter.z < zFwd)` never true** — dragged stays in front of target (z > zFwd) because window planes face camera and dragged's plane parallel-with-target keeps small positive z gap. Telegraph is co-planar but dragged window is hovering forward.
- **H7: Z-clamp fires but the user can't see it** — z change is too small (1cm) to perceive as "lay on surface". Pseudomirror windows have visible separation/adhesion because they're parented to mirror node, sharing exact transform.
- **H8: Real "pseudomirror collision" is parent-swap, not depth-clamp** — pseudomirror windows are parented to the mirror Node, so they inherit transform exactly. Reproducing requires either dynamic reparent (dragged.parent = target during intent) or full pose mirror (position+rotation match every frame, including pose update — which previously caused the freeze).

## Things tried and what happened

| Attempt | Result |
|---------|--------|
| Full Z-stick (position+rotation+pose update) | Window FROZE in place. Drag broken. |
| No stick at all, telegraph only, commit on release | Telegraph worked. Commit "didn't move" per user (logs not captured to verify if commit fired). |
| Lateral position override during drag (snap dragged to landing pose) | Side snaps oscillated/flickered (override moved dragged out of overlap → next scan no intent → cycle). Stack worked because override kept dragged on target. |
| Z-only clamp (current) | Still no surface adhesion visible. Commit still doesn't visibly move window. |

## Critical missing data

**Tail journal during a test:**
```bash
journalctl --user -f | grep kwinvr
```

Then drag → telegraph → release. Capture the `Snap release:` and any `Snap commit:` lines. This single piece of data discriminates H1 vs H2 vs H3.

## Pseudomirror reference for adhesion

`KwinPseudoOutputMirror.qml` is the reference for "windows lay on surface". Look at how `KwinApplicationWindow` is parented in screen state: `parent: outputMirrorRepeater.findPseudoOutputByOutput(...)`. Position derived from `centerOffset(frameGeometry, output.geometry, zOffset, ppu)` — flat in mirror's local frame.

**Key insight:** pseudomirror collision is parent-relative coordinate sharing, not 3D distance clamping. If we want dragged to lay on target like a pseudomirror window, we need to put it in target's local coordinate space — either by reparenting (dynamic, fragile) or by replicating target's full transform (the freeze pitfall).

## Files for resuming

- Spec issue: https://github.com/Bake-Ware/kwin-vr/issues/14
- Branch state: `git status` on `feat/window_dock`
- Build cmd: `cd /home/bake/kwin-vr/build && cmake --build . --target vr -j$(nproc) && cmake --install src/plugins/vr`
- Smoke test: logout/login, click VR mode, drag VR window over another, watch `journalctl --user -f | grep kwinvr`

## Suggested next debug step

1. User tails journal during a single test.
2. Capture exact log output of one drag→release cycle with telegraph visible.
3. Match output against H1/H2/H3 to localize the bug.
4. Fix that one specific issue. Smoke test. Iterate.

Do not re-attempt full pose stick (caused freeze). Do not pile on more conditional logic without log evidence.
