# Impl — scaffold types

**Status:** done
**Commits:** `8b11b835a3` — `vr: work_surfaces phase 1 — scaffold types`
**Design refs:** [design-data-model](design-data-model.md)

## Goal

Land the `WorkSurface` + `WorkSurfaceRegistry` QML types and add the per-window `workSurface` + `curvatureOverride` properties, without wiring any behavior. Compile clean, no runtime regression. This is the foundation the rest of the feature builds on.

## What shipped

- `WorkSurface.qml` created with properties only (`surfaceId`, `curvature`, `members`, `adjacency`). No functions.
- `WorkSurfaceRegistry.qml` created with placeholder `_newId()` and `surfaceForWindow(w)` lookup. No lifecycle logic yet.
- `WorkSurface.qml` and `WorkSurfaceRegistry.qml` registered in `src/plugins/vr/CMakeLists.txt` QML_FILES list.
- `KwinTransientWindow.qml` gained `workSurface` (default `null`) and `curvatureOverride` (default `NaN`) properties.
- `XrScene.qml` instantiates `WorkSurfaceRegistry { id: workSurfaces }` as a sibling of `WindowSnapManager`. Not yet wired to the snap manager.

## Files touched

- `src/plugins/vr/CMakeLists.txt` — added 2 QML files.
- `src/plugins/vr/qml/WorkSurface.qml` — new file.
- `src/plugins/vr/qml/WorkSurfaceRegistry.qml` — new file.
- `src/plugins/vr/qml/KwinTransientWindow.qml` — added 2 properties.
- `src/plugins/vr/qml/XrScene.qml` — instantiated registry.

## Code refs

- `WorkSurface.qml:18-24` — property block defining the data model.
- `WorkSurfaceRegistry.qml:22-31` — property + placeholder helpers.
- `KwinTransientWindow.qml:35-40` — new per-window properties with inline rationale.
- `XrScene.qml:258-262` — registry instantiation.
- `CMakeLists.txt:78-79` — QML_FILES additions.

## Verification

- `cmake --build . --target vr` clean.
- `sudo cmake --install .` + `dbus-send ... org.kde.KWin.replace` → kwin_wayland restarted cleanly. No QML `ReferenceError` or `TypeError` in journal (verified with `journalctl --user -u plasma-kwin_wayland.service`).
- VR session continues to launch; existing Dock & Stack behavior unchanged (functional regression test = dock two windows, stack them, nothing breaks).

## Open issues / follow-ups

- Registry not yet consumed by `WindowSnapManager._commitSnap` — next chunk ([impl-registry](impl-registry.md)).
- `surfaceForWindow()` is a trivial passthrough; kept in case future lookups need more logic.
- `curvatureOverride` uses NaN sentinel — callers must `isNaN()` check before using the value.

## Commit history

```
8b11b835a3 vr: work_surfaces phase 1 — scaffold types
```
