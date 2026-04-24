# Design — curvature

## Rendering

Window delegates (`KwinSurfacedWindow3D`, `KwinDecoratedSurfacedWindow3D`) currently use flat plane geometry. Phase 1 swaps to `CurvedPlaneGeometry` (already exists in-tree at `src/plugins/vr/curvedplanegeometry.cpp/h`, used by `VrHudPlane.qml`) bound to the effective curvature.

Range: `0.0` (flat) to `6.0` (matches `hudCurvature` kcfg range). Unit is total arc angle in radians (see `curvedplanegeometry.cpp:80`).

## Effective curvature — the resolution chain

```qml
readonly property real effectiveCurvature:
    !isNaN(client.curvatureOverride) ? client.curvatureOverride
        : (client.workSurface ? client.workSurface.curvature
            : KWinVRConfig.defaultWindowCurvature)
```

Three-tier fallback:

1. Window's `curvatureOverride` (NaN = not set, any real = override active).
2. Window's `workSurface.curvature` if the window is a surface member.
3. `KWinVRConfig.defaultWindowCurvature` global default.

The delegate binds `CurvedPlaneGeometry.curvature` to this expression. Any tier change propagates live — surface curvature change updates all members that don't have their own override; global default change updates all windows that have neither override nor surface.

## UV projection / pose on surface

See [design-uv-projection](design-uv-projection.md) for the positional/rotational side. Curvature propagation is orthogonal — positioning places the window on the surface manifold; curvature shapes the window's own curve so it's tangent-continuous with the surface.

## Gestures

### Alt + scroll wheel on a hovered window

Quick curvature nudge without opening a popup. Step = `KWinVRConfig.curvatureScrollStep` (default `0.1`). Scroll up → increase curvature, scroll down → decrease. Clamped 0.0–6.0.

Sets the **hovered window's** `curvatureOverride` — always per-window. Doesn't touch surface curvature. If the user wants to adjust the whole group, they use the group-tab slider.

Mirrors existing `scrollGrab` pattern in `XrScene.qml:167-178` (which uses wheel for depth). Alt modifier disambiguates.

### Window-tab curvature button + slider popup

Click the `∿` button on a window's own tab → horizontal `PlasmaComponents3.Slider` appears below the tab, range 0.0–6.0. Drag to set `curvatureOverride`. Click elsewhere or click the button again → dismiss.

Live-binds to `client.curvatureOverride` on drag (not just on release), so the window curves in real time.

### Group-tab curvature button + slider popup

Same widget, different scope. Setting the slider:

1. Assigns the value to `surface.curvature`.
2. Clears `curvatureOverride` on all members (sets to NaN).

This is the "flatten to surface" operation. Per user: "whatever is being set is what the setting should be" — the group slider sets the group, and members drop any individual overrides so they all conform.

## Config keys

Added to `src/plugins/vr/kwinvr.kcfg`:

```xml
<entry name="defaultWindowCurvature" type="Double">
  <label>Default curvature for VR windows and work surfaces</label>
  <default>0.0</default>
  <min>0.0</min>
  <max>6.0</max>
</entry>

<entry name="curvatureScrollStep" type="Double">
  <label>Curvature change per Alt+wheel tick</label>
  <default>0.1</default>
  <min>0.01</min>
  <max>1.0</max>
</entry>
```

KCM page gets a spinbox for `defaultWindowCurvature` and `curvatureScrollStep` in the appearance tab (or a new "Windows" tab if existing tabs don't fit).

## Stack cascade + curvature

Stack cascade offsets (`step * k` in `_computeLandingPose` at `WindowSnapManager.qml:220`) are applied in surface-local tangent frame at the stack base's UV position. This means cascades bend with the manifold — stack of 3 windows on a curved surface follows the curve, not world-straight. Decision captured in [overview](overview.md) resolutions; implementation lands in the UV-projection commit.
