> **Provenance:** salvaged from the 6.5.5-era `archive/stabilization` tag (original path
> `extras/DESIGN-multi-hmd.md`). Still the live design reference: "spectator-2d free camera"
> is the M2 flat-monitor mode, and the role/priority model feeds M4 runtime profiles.

# Multi-HMD Design Notes

Status: Future feature. Documenting now so profile system doesn't paint us into a corner.

## Roles

- **primary** — Owns mouse/keyboard input. Can move windows, resize, interact with
  desktop content. One at a time. First local device gets this by default.
- **spectator** — HMD viewer. Sees the same VR environment, controls own head pose
  only. Cannot interact with desktop content.
- **spectator-2d** — Flat viewport on a monitor. Two sub-modes:
  - **free camera** — viewer controls their own viewpoint via mouse look.
  - **follow primary** — camera locked to primary's head pose. "Let me show you
    something" mode. Only safe for 2D viewers (hijacking an HMD user's view = nausea).

## Detection Priority

1. **local** — physical device plugged into this machine (USB/DP). Autostart VR.
2. **remote** — network headset (WiVRn, etc). Autostart VR.
3. **fallback** — no hardware. Test mode (Monado qwerty driver). Manual activation only.

Within each class, first match gets primary role. Additional matches become spectators.

## Primary Handoff (Super+V)

Quick-switcher overlay (like Alt+Tab but for HMD roles):
- Shows all connected devices with current roles
- Cycle with arrow keys or repeated Super+V, Enter to confirm
- Selected device becomes primary, old primary becomes spectator
- Instant transition — no reconnection, no mode switch
- Just remaps: whose pose drives the interaction ray, whose HID events move the cursor

## Use Cases

- **Movie night**: Two local HMDs, one primary (has playback controls), one spectator.
- **Presentation**: Host is primary (local), audience is spectators (remote Quest 3s
  via WiVRn + 2D views with follow-primary for screen-share equivalent).
- **Pair programming**: Two local HMDs. Either can be primary. Super+V to hand off
  when "let me drive" happens.
- **Demo to peasants**: Primary on HMD, 2D spectator view on the laptop screen with
  follow-primary toggle so the audience sees what the presenter sees.

## Architecture (future)

Current: 1 KWin VR -> 1 Monado -> 1 OpenXR session -> 1 HMD.

Future: KWin VR treats each HMD as an output with its own view transform. The scene
is rendered once. Each viewer gets a reprojected view based on their individual pose.
The 2D spectator is just another output that happens to be flat.

The custodian tracks all matched profiles and reports them. Today it activates the
highest-priority one. Tomorrow it activates all of them as viewers.

## Profile Schema (current)

```
VR_DETECT_TYPE=local|remote|fallback
VR_AUTOSTART=true|false
```

No priority int, no role field yet. When multi-HMD ships, add:

```
VR_ROLE=primary|spectator|spectator-2d    (default: auto-assigned)
```

Existing profiles don't break — first match gets primary, rest get spectator.
