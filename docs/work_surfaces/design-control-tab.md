# Design — control tab

Theme-styled folder-tab widget at top-right of every window and every surface.

## Visual

```
                  ┌──────────┐
                  │ ≡  ∿ ◫ □ │   ≡ = grip | ∿ = curve | ◫ = trans (later) | □ = pip (later)
 ┌────────────────┴──────────┴─┐
 │         Window body         │
 └─────────────────────────────┘
```

- Short tab, right-justified at top edge. Not full-width.
- Height: `KWinVRConfig.windowControlTabHeight` (default 28 px).
- Width: content-driven, capped at `KWinVRConfig.windowControlTabMaxWidth` (default 180 px).
- Rides the curve — child node of window delegate (or surface node for group-tab). Bends with the manifold tangent at the top edge.

## Scope — window-tab vs group-tab

| Tab | Shown on | Slider scope |
|-----|----------|--------------|
| Window-tab | Every window (solo or grouped) | `client.curvatureOverride` only. Doesn't touch surface or siblings. |
| Group-tab | Surface bounding box, only when `members.length > 1` | `surface.curvature` + clears all member `curvatureOverride` to NaN (flatten-to-surface). |

Same visual spec, same buttons. Differ only in what their sliders set.

**"Whatever is being set is what changes"** — no Alt-modifier semantics, no hidden state. If you move the slider on a window-tab, that window changes. If you move the slider on a group-tab, the group changes and members conform.

## Contents

Left → right:

1. **Grip icon** (`≡`) — visual hint for the drag affordance. The grip itself and any non-icon pixel on the tab are draggable area; icon buttons are not.
2. **Curvature button** (`∿`) — click → slider popup below tab. Popup dismisses on click-outside or second button click. Slider live-binds to the tab's scope.
3. *(future)* **Transparency button** (`◫`) — same popup-slider pattern.
4. *(future)* **PIP button** (`□`) — click opens 4-corner picker popup. Tap corner → pin as PIP.
5. *(future)* **Pin button** — toggle pin state.

Close is **NOT** on the tab. Close lives on the existing SSD decoration (for decorated windows) and on the radial menu. Borderless clients without SSD close via radial / keybind only. Explicitly accepted trade-off.

## Drag behavior

- Non-icon tab pixel = drag affordance.
- Window-tab drag: dragging behaves as if user had grabbed the window body — group-rigid if in surface, solo if not. Shift modifier still works (detach).
- Group-tab drag: always group-rigid. Shift is a no-op on group-tab.

## Unconditional application

VR wrapper adds the tab to **all** windows regardless of client SSD preference. SSD-decorated windows get SSD + our tab. Borderless Wayland-native windows get only our tab. VR treats itself as a separate UX layer — one contract for all windows.

## Theme sourcing

```qml
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
```

- Icons: `Kirigami.Icon` with system theme names (`"drag-handle"` or `"handle"` for grip, `"transform-shear"` or a custom curvature icon for `∿`, etc.).
- Colors: `Kirigami.Theme` tokens.
- Slider: `PlasmaComponents3.Slider`.
- Buttons: `PlasmaComponents3.ToolButton` with `icon.source` set.

**Risk:** `PlasmaComponents3.Slider` drag interaction in VR pointer space may not work cleanly — the slider's internal `MouseArea` may swallow events the VR input filter expects to route through `XrScene` hit-testing. Fallback: hand-rolled slider widget with `Kirigami.Theme` colors, same visual language. Flagged as open question; prototype early.

## Hit-testing

Tab is a separate pickable Node sibling of the window plane. Icon buttons have their own `MouseArea` + `grabHandle: null` so they absorb clicks for actions; the non-icon area falls through to the tab's root MouseArea, which forwards to the standard "grab the window/surface" path.

Popups (slider, PIP picker) are additional Nodes instantiated on click, anchored in surface-local space to the originating button. Dismissed on click-outside (global pickray release event on non-popup target) or second click on the button.

## Placement — group-tab anchor

Group-tab appears at top-right of the surface's **bounding box**, not at a specific member. When members are added/removed, bbox changes, tab moves. The tab node is a child of the surface node, positioned at `(bbox.right, bbox.top)` in surface-local space.

When only one member → group-tab hidden (no group-level identity to show).

## Files that ship this

- `src/plugins/vr/qml/WindowControlTab.qml` — the folder-tab widget. Parameterized by scope property (`"window"` or `"group"`) + target (window client or surface).
- `src/plugins/vr/qml/CurvatureSliderPopup.qml` — slider popup.
- `src/plugins/vr/qml/KwinSurfacedWindow3D.qml`, `KwinDecoratedSurfacedWindow3D.qml` — instantiate window-tab as child.
- `src/plugins/vr/qml/WorkSurface.qml` — instantiate group-tab as child when members > 1.

## Commits that will touch this

- `work_surfaces: control tab widget` — WindowControlTab + CurvatureSliderPopup + instantiate on every window.
- `work_surfaces: group-tab on surface` — instantiate on surfaces when members > 1.
- `work_surfaces: plasma slider fallback` — only if stock slider misbehaves in VR (decision gate mid-feature).
