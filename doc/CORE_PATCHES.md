# Core KWin Patches (everything outside `src/plugins/vr/`)

This is the exhaustive ledger of modifications to core KWin carried by this fork.
Keeping this list small and documented is what keeps rebases onto newer KWin feasible.

**Vanilla base:** commit `11a5943607` ("Update version for new release 6.6.3") — stock KWin 6.6.3.
**Patch series author:** almost entirely lightofmysoul's `upstream/6.6.3_vr` series
(invent.kde.org/lightofmysoul/kwin). This fork's own out-of-plugin delta on top of that
series is currently **one change**: the logind DRM-lease fix in `src/wayland/drmlease_v1.cpp`
(`2564e38d40`).

**Reproduce/audit this list:**
```bash
git diff --stat 11a5943607..main -- . ':!src/plugins/vr' ':!po' ':!doc' ':!*.md'
```
Run this after every merge to `main`; if a file appears that isn't listed below, either
document it here in the same PR or move the change into the plugin.

## By subsystem

### DRM leasing (hand the glasses display to the OpenXR runtime)
- `src/wayland/drmlease_v1.{cpp,h}`, `drmlease_v1_p.h` — wp_drm_lease_v1 negotiation; **bake's logind fix lives here**
- `src/backends/drm/drm_backend.cpp` — leasable-only config changes skip atomic test
- `src/backends/drm/drm_gpu.cpp`, `drm_output.{cpp,h}`, `drm_virtual_output.cpp` — leasable flag plumbing, virtual modes
- `src/core/backendoutput.{cpp,h}`, `outputbackend.h`, `outputconfiguration.h` — `isLeasable()`/`setLeasable()` capability
- `src/outputconfigurationstore.{cpp,h}` — persist leasable state
- `autotests/drm/` — mock DRM test for leasing (mockDrmTest.cpp; build with `BUILD_TESTING=ON`)

### Window/3D integration (VR plugin needs richer window control)
- `src/window.{cpp,h}` — VR window properties, pointer-lock allowance, interactive move/resize hooks (largest core change, ~160 lines)
- `src/workspace.{cpp,h}`, `src/scripting/workspace_wrapper.{cpp,h}` — workspace queries for the plugin
- `src/scripting/windowthumbnailitem.{cpp,h}` — thumbnail scale/invalidation for 3D window rendering modes
- `src/internalwindow.{cpp,h}` — transientness support for internal windows
- `src/xdgshellwindow.{cpp,h}`, `src/waylandwindow.cpp`, `src/x11window.cpp` — geometry/buffer propagation
- `src/scene/windowitem.cpp` — offscreen rendering fix
- `src/compositor.cpp` — skip rendering virtual outputs
- `src/decorations/decoratedwindow.cpp`, `src/useractions.{cpp,h}` — decoration/menu behavior in VR

### Input
- `src/input.{cpp,h}`, `src/pointer_input.{cpp,h}` — pointer position limiting, hovered-window resolution customization (VR pointer routing)
- `src/options.h` — option plumbing

### Rendering
- `src/opengl/eglbackend.{cpp,h}` — drm format filter support, QPA/GL adoption
- `src/core/renderbackend.{cpp,h}` — backend hooks
- `src/plugins/qpa/window.cpp` — internal-window QPA tweaks

### Wayland protocol surface
- `src/wayland_server.{cpp,h}`, `src/wayland/surface.h`, `src/wayland/subcompositor.h` — surface/exclude-from-capture plumbing

### Build/meta
- `CMakeLists.txt`, `src/plugins/CMakeLists.txt`, `.gitignore`, `PKGBUILD`
- `src/kscreenintegration.cpp` — minor integration fix

## Rebase policy

Stay on the 6.6.3 base through v1.0. `upstream/6.6.4_vr` is a clean rebased ~21-commit
series and the template for the next rebase — schedule one rebase window **after** v1.0,
never mid-milestone.
