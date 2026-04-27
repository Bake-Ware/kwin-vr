# VolumetricStacker — implementation status, planned vs delivered

Branch: `feat/volumetric_stacker` (off `feat/curved_plane`)
Tip: `8a5c5dc715` (as of 2026-04-27)
Status: all 8 planned phases committed locally. Three open regressions surfaced in VR validation. Not pushed.

Plan source: `/root/.claude/plans/valiant-nibbling-rossum.md`
Architecture source: `docs/curved_plane/architecture.md`

## Phase ledger

| Phase | Commit | Planned | Delivered | Notes |
|-------|--------|---------|-----------|-------|
| A | `d9c638f2e9` | Rename ZStacker → VolumetricStacker, ILayoutMode strategy registry, StackMode | ✅ as planned | Bit-identical Stack mode; no behavior change for current call sites. |
| B | `6d49da76d8` | Cascade/SnapRow/Free modes + wire CurvedPlane | ✅ scope reduced | Per-item helpers + LayoutEngine QML singleton. CurvedPlane delegates inline math to the engine. **Batch ILayoutMode subclasses for Cascade/SnapRow/Free were deferred** — there are no batch callers yet (StackMode is the sole batch impl). Will land when migration creates batch users. |
| C | `6812db9aab` | Layer enum + OcclusionAwareMode + layer-pass dispatch | ✅ scope reduced | Layer Q_ENUM (Content/Transient/Overlay/HUD) + OcclusionAwareMode helper class + LayoutEngine.classifyOcclusion + kcfg gaps. **Layer-pass dispatch in VolumetricStacker batch was deferred** — would only matter when a real batch consumer asks for layered Z, and none exists yet. |
| D | `4d61e1bb70` | Pseudomirror → CurvedPlane(Free) | ✅ scope reduced | Just gated `KwinWindowThumbnail3D` / `KwinWaylandSurface3D` curvature on `client.vr` as an interim wallpaper-curve fix. **Structural pseudomirror migration moved into Phase E** because the abductor curvature path needs windows to be CurvedPlanes too. |
| E | `f201b2667e` + `8a5c5dc715` | KwinApplicationWindow → CurvedPlane(None) | ✅ as planned | Pseudomirror is now `CurvedPlane(Free, _isPseudomirror, stackChildren)`. KwinApplicationWindow is `CurvedPlane(None)` wrapping embedded KwinTransientWindow rendering. XrScene state machine deleted. Curvature inheritance via Qt-parent walk in window thumbnails. Container border decoration. Pseudomirror self-suppresses control tab. **Follow-up `8a5c5dc715` patched: PlaneInteractionManager grab order race; `detachWindowToVR` parent-chain depth (Phase E added a layer); pseudomirror curvature bound to `defaultWindowCurvature`.** |
| F | `d07c2a25bd` | Strip legacy stack props + OcclusionAware migrate | ✅ scope reduced | Stripped `preSnapGeom` / `stackedOnto` / `stackIndex` / `stackFocusRequested` from KwinTransientWindow. CurvedPlane Free+stackChildren ranks children by their `stackingOrder` property — focus-rises desktop above siblings. **OcclusionAware migration of transient stacks was NOT done** — would need batch layer-pass logic in VolumetricStacker first. Current transient stacks still use the legacy Stack mode (was ZStacker). |
| G | `516646233e` | Delete WindowSnapManager | ✅ as planned | File deleted (-557 lines). XrScene snapManager block + telegraphGhost removed. **Side effect**: there's no longer a snap-preview during drag (telegraph ghost was specced in arch.md §"Snap mode — Insertion telegraph" but never re-implemented). |
| H | `a6d5750ec8` | Docs + memory + wiki + Free-at-0 dissolve | ✅ partial | Mode-aware dissolve done. architecture.md updated (modes, layers, OcclusionAware, file structure, kcfg, decorations, pseudomirror). Memory files updated. **Wiki not updated** — defer until validation + push. |

## Architecture compliance

✅ Everything-is-a-CurvedPlane (windows, pseudomirrors, snap groups, stack groups, free containers).
✅ Property-driven behavior, no type checks.
✅ Plane queries registry for abductor; never reads it directly.
✅ Single-list invariant (`removeFromAllSlots` on every `addChild`).
✅ Top-level: render = intrinsic. Abducted: render = abductor.computeChild*.
✅ No reparenting on abduction.
✅ Single curvature setting (`KWinVRConfig.defaultWindowCurvature`) drives pseudomirror + free windows + (via abductor push) all hosted children.
✅ Mode-specific dissolve thresholds: Free=0, Snap/Stack<2, pseudomirror never.
✅ Plane-as-parent for snap/stack — no window is a "root", all members are siblings of a container plane.

## Architecture deviations

### 1. Drag mechanism (significant)
**arch.md §"Drag = abduction by ray"** specifies:
```
grab(plane):
    registry.removeFromAllSlots(plane.planeId)
    pickRay.slots = [{ planeId, overrides: { position: gripOffset } }]
    pickRay.relayout()
```
Pick-ray would BE the abductor. Position binding fires automatically as ray moves.

**Delivered:**
PlaneInteractionManager sets `plane.isGrabbed = true` to suspend the position/rotation bindings, then `Xray.applyRelativePose` writes pose imperatively each frame. Pick-ray is NOT registered as an abductor.

Functionally equivalent for the move-with-ray case but architecturally different. Worth realigning if/when we revisit drag.

### 2. Snap-insertion telegraph not implemented
**arch.md §"Snap mode — Insertion telegraph"** specifies a thin vertical gap-widening line during drag at the insertion index.

**Delivered:**
`telegraphGhost` (legacy preview) deleted in Phase G. No replacement. The container border (Phase E) only renders post-commit.

### 3. Layer-aware batch dispatch deferred
**Plan doc** said Phase C would add layer-pass logic + cross-layer Z-share to VolumetricStacker batch.

**Delivered:**
Layer enum + OcclusionAwareMode helper + LayoutEngine.classifyOcclusion exist, but `VolumetricStacker::recomputeLayout` is still single-pass Stack-only. No batch caller yet asks for layered Z.

### 4. Transient stacks not on OcclusionAware
**Plan doc** said Phase F would migrate transient stacks to `Mode.OcclusionAware + Layer.Transient`.

**Delivered:**
KwinTransientWindow's two transient repeaters still use VolumetricStacker(Stack mode, default Layer). Equivalent to legacy ZStacker behavior — works, but doesn't structurally fix transient layering across siblings on the same pseudomirror. The pragmatic stackingOrder-rank fix (Phase F) gives focus-rise behavior so the desktop-right-click case works.

### 5. Cascade/SnapRow/Free batch ILayoutMode classes deferred
Per-item helpers exist (`CascadeMode::positionAt`, etc.). Batch interface implementations don't. Land when needed.

## Open regressions (from VR validation 2026-04-27)

### A. Stacking and snapping not firing
**Symptom:** dragging a free-VR window over another doesn't trigger snap/stack on release.

**Likely cause:** the only ray-grab paths that set `xray.grabbedObject` to a CurvedPlane are:
1. `VrWindowManipulation.movingResizingWindowWatcher` — fires when KWin enters window-move state (titlebar drag, Alt+drag, programmatic move). Click-on-body without Alt does NOT enter window-move.
2. `detachWindowToVR` — when a screen-state window crosses output edge.

If the user's testing gesture is click-on-body-and-drag, KWin treats it as a click event and `client.move` stays false → no `currentMovingResizingWindow` → no `xray.grabAndAlign` → PlaneInteractionManager.`_grabbedPlane` stays null → snap detection disabled.

**Open question:** is click-on-body intended to initiate a VR ray-grab? Architecture doc doesn't address this gesture explicitly. If yes, needs a new grab path that bypasses KWin's window-move signal.

**Verification path:** test snap/stack with explicit titlebar drag or Alt+drag on a free-VR window. If those work, the issue is purely a missing gesture binding for click-on-body.

### B. No drag preview / telegraph
**Symptom:** during drag toward a target, no visual indicator of what action will fire on release.

**Cause:** Phase G removed `telegraphGhost`. Container border (Phase E) only renders after commit creates a container. arch.md §"Snap mode — Insertion telegraph" was never implemented for the new system.

**Fix shape:** add a preview Model (shaped per `_snapAction`: row gap line for SnapRow, cascade ghost for Stack) parented to the snap target, visibility bound to `PlaneInteractionManager._snapTarget` + `_snapAction !== None`. Mirror legacy telegraphGhost's pattern but read state from PlaneInteractionManager instead of WindowSnapManager.

### C. Pseudomirror curve flicker (curved → flat after adding a window)
**Symptom:** pseudomirror starts curved (correct, follows `defaultWindowCurvature`); after adding a window back to the pseudomirror, it goes flat.

**Repro hint from user:** "presents after adding a window back to pseudomirror."

**Hypotheses (untested):**
- `slotsRevision` bump triggers some re-evaluation that imperatively writes `intrinsicCurvature`. (No code I can see does this.)
- `KWinVRConfig.defaultWindowCurvature` value transitions or the `||` fallback evaluates differently. (Both should be stable.)
- Ancestor walk in `KwinWindowThumbnail3D._ancestorPlaneCurvature` becomes stale on slot membership change. (The walk reads `effectiveCurvature` of the nearest CurvedPlane ancestor; that ancestor's effectiveCurvature should track abductor.computeChildCurvature → pseudomirror.intrinsicCurvature, which is bound to defaultWindowCurvature.)
- Some interaction between `_pseudoOverrides` (which only writes `position`, not `curvature`) and `updateSlotOverrides` — `Object.assign({}, slot.overrides, newOverrides)` would *preserve* a previous `curvature` override, but no code sets one in the first place.

**Unverified theory:** when a window is re-added (`pseudo.addChild`), addChild calls `registry.removeFromAllSlots(child.planeId)` first. If the child was previously a slot of a Snap/Stack container that hadn't dissolved yet, removeFromAllSlots triggers `_maybeDissolve` on that container, which writes `lone.intrinsicPosition` / `lone.intrinsicRotation` imperatively. Doesn't touch curvature, so this shouldn't be it.

**Next debug step:** add a `console.log(Logger.kwinvr, "pseudo curvature:", root.intrinsicCurvature)` binding to KwinPseudoOutputMirror with a watcher on the property change. Capture exact frame the value transitions. Or add a watch on KWinVRConfig.defaultWindowCurvature.

## Files touched

C++ (new + renamed):
```
src/plugins/vr/zmargins.h                            (split out from former zstacker.h)
src/plugins/vr/volumetricstacker.{h,cpp}             (was zstacker.{h,cpp})
src/plugins/vr/layoutengine.{h,cpp}                  (new — QML singleton facade)
src/plugins/vr/layoutmodes/ilayoutmode.h             (new — batch interface)
src/plugins/vr/layoutmodes/stackmode.{h,cpp}         (new — bit-identical Z accumulator)
src/plugins/vr/layoutmodes/cascademode.{h,cpp}       (new — per-item helper, no batch yet)
src/plugins/vr/layoutmodes/snaprowmode.{h,cpp}       (new — per-item helper, no batch yet)
src/plugins/vr/layoutmodes/freemode.{h,cpp}          (new — per-item helper, no batch yet)
src/plugins/vr/layoutmodes/occlusionawaremode.{h,cpp}(new — sticky footprint-max-Z helper, no batch yet)
```

QML modified:
```
src/plugins/vr/qml/CurvedPlane.qml                  control tab self-suppress for pseudomirror;
                                                    container border; mode-aware dissolve;
                                                    _stackRank by stackingOrder; LayoutEngine
                                                    delegation for snap/stack/free positions
src/plugins/vr/qml/KwinPseudoOutputMirror.qml       Node → CurvedPlane(Free, _isPseudomirror,
                                                    stackChildren); intrinsicCurvature bound to
                                                    defaultWindowCurvature
src/plugins/vr/qml/KwinApplicationWindow.qml        KwinTransientWindow → CurvedPlane(None) with
                                                    embedded rendering child; client.vr/output/
                                                    frameGeometry → addChild/removeFromAllSlots
src/plugins/vr/qml/KwinTransientWindow.qml          stripped legacy snap props
src/plugins/vr/qml/KwinWindowThumbnail3D.qml        curvature via _ancestorPlaneCurvature walk
src/plugins/vr/qml/KwinWaylandSurface3D.qml         same walk pattern
src/plugins/vr/qml/PlaneInteractionManager.qml      pose-capture-then-suspend-then-detach order
src/plugins/vr/qml/VrWindowManipulation.qml         detachWindowToVR uses .grabHandle (Phase E
                                                    added a parent layer); dropped vrPlane refs
src/plugins/vr/qml/XrScene.qml                      delegate state machine removed; pseudomirror
                                                    Component.onCompleted writes intrinsic*;
                                                    snapManager + telegraphGhost gone
src/plugins/vr/CMakeLists.txt                       SOURCES + QML_FILES list updates
src/plugins/vr/kwinvr.kcfg                          occlusionIntraLayerGap, occlusionLayerGap
src/plugins/vr/kcm/ui/WindowSpacingSetup.qml        (untouched in this branch)
docs/curved_plane/architecture.md                   strategy pattern, layers, OcclusionAware,
                                                    file structure split, pseudomirror,
                                                    decorations, kcfg, dissolve thresholds
```

QML deleted:
```
src/plugins/vr/qml/WindowSnapManager.qml            (-557 lines, replaced by PlaneInteractionManager)
```

## Open questions for fresh-eyes session

1. **Snap regression A** — debug click-on-body vs titlebar-drag distinction. If the answer is "we want click-on-body to ray-grab", design the new grab path. If "titlebar-drag is fine", document the gesture and move on.
2. **Telegraph regression B** — implement insertion preview, or accept missing visual feedback short term?
3. **Curve flicker C** — instrument with Logger output, capture the moment of transition. Most likely a binding break we haven't traced.
4. **Push or rebase?** — branch is 9 commits ahead of `feat/curved_plane`. Likely answer: validate fixes for A/B/C, then push as a single PR. But maybe squash some of A–H first.
5. **Wiki update** — pending per `feedback_kwin_vr_wiki.md`. Touch when push is imminent.
