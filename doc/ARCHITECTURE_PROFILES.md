> **Provenance:** salvaged from the 6.5.5-era `archive/stabilization` tag (original path `ARCHITECTURE.md`).
> The custodian *daemon* it describes was retired — the 6.6.3 line uses DRM leasing + in-plugin
> auto-lease instead. The **profile-matching principle** (no device names/vendor IDs in code) is
> re-adopted as the contract for M3 (SBS heuristic removal, hot-plug) and M4 (runtime profiles).
> Sections describing the custodian process are historical context, not current architecture.

# kwin-vr Architecture Guidelines

## Core Principle: Device-Agnostic Profile Matching

All device-specific logic must live in **configuration profiles**, not in code.
Code must never contain `if vendor == "xreal"` or `if output->name() == "DP-1"` style branches.
Every time context compacts and work resumes, this document is the contract that prevents regression.

---

## The Two Processes

### 1. `kwin-vr` — The KWin Plugin (Wayland compositor side)
Runs inside `kwin_wayland`. Owns all VR state and UI:
- Activating/deactivating VR mode (`vrActive`)
- Managing the virtual output (Virtual-T)
- Placing and fullscreening the OpenXR compositor window
- Applying output configuration via KWin's internal API (never kscreen-doctor)
- Receiving trigger events from the custodian and acting on them

**Does NOT do hardware detection. Does NOT contain device names or vendor IDs.**

### 2. `kwin-vr-custodian` — A Dedicated System Service (NEW, replaces mode-watcher)
A small, always-running system/user service (`systemctl status kwin-vr-custodian`).
Written in a real language (C++ or Python), not bash.
Owns all hardware observation and event routing:
- Watching for EDID/output changes (DRM uevents or KWin D-Bus signals)
- Watching for service state changes (e.g. WiVRn server appearing on D-Bus)
- Watching for USB device hotplug (udev events)
- Matching observed events against loaded profiles
- Sending USB HID init commands defined in profiles
- Notifying the KWin plugin via D-Bus when a profile matches or unmatches
- Starting/stopping the OpenXR runtime (Monado, WiVRn) via systemd D-Bus

**Does NOT contain device names or vendor IDs. Reads everything from profiles.**

---

## Configuration Profiles (`/etc/vr-profiles.d/`)

Each profile is a file describing one VR target. The custodian loads all profiles at startup and re-reads them on `SIGHUP` or inotify change.

### Profile Identification
Profiles are matched by a manifest index or by filename convention.
Suggested: each profile declares its own match criteria inside the file.
No hardcoding of filenames in code — the custodian scans the directory.

### What a Profile Contains (all fields optional/conditional)

```ini
# Identity
NAME = Xreal Air Gen 1
TYPE = sbs_glasses          # see Profile Types below

# Trigger: what event causes this profile to activate
TRIGGER = edid              # edid | service | manual | always

# For TRIGGER=edid: match criteria (all must match)
# EDID_VENDOR is the 3-letter code from bytes 8-9 of the raw EDID (5-bit encoding),
# NOT the USB vendor name or brand name. Verify with edid-decode or raw sysfs bytes.
EDID_VENDOR = MFR
EDID_PRODUCT_ID = 0x1234
SBS_MODE = 3840x1080        # mode that signals VR is requested
DESKTOP_MODE = 1920x1080    # mode that signals VR should stop

# For TRIGGER=service: D-Bus service name to watch
# SERVICE_NAME = net.wivrn.Server

# Hardware init (runs once when device is first detected, before VR activates)
# These replace ALL shell scripts. The custodian executes them directly.
HID_INIT_VENDOR = 3318
HID_INIT_PRODUCT = 0424
HID_INIT_INTERFACE = 4
HID_INIT_PAYLOAD_2D = 01:00:00:...   # hex bytes to send for desktop mode
HID_INIT_PAYLOAD_3D = 01:01:00:...   # hex bytes to send for SBS mode

# Display configuration
VR_WIDTH = 3840
VR_HEIGHT = 1080
VR_REFRESH = 60
VR_SCALE = 1
VIRTUAL_WIDTH = 1920
VIRTUAL_HEIGHT = 1080

# OpenXR runtime
OPENXR_RUNTIME = monado     # monado | wivrn | none

# DP link training hint (optional, for displays needing explicit retrain)
DP_FORCE_RETRAIN = true
```

### Profile Types

| TYPE | Description | Trigger |
|------|-------------|---------|
| `sbs_glasses` | AR glasses with SBS mode switch | EDID mode change |
| `hmd` | Traditional PC VR headset | EDID presence |
| `streaming` | WiVRn or similar network VR | Service appears on D-Bus |
| `flat_monitor` | Normal display, VR on 2D screen | Manual (user initiates from settings) |

The `flat_monitor` type is a deliberate fallback. If the user starts VR from the settings page and no other profile matches, VR activates on whatever the current primary display is. This prevents dead-end states and enables keyboard/gamepad navigation in VR (WASD etc.) and recording of the VR interface.

---

## Event Sources the Custodian Watches

The custodian is not just an EDID watcher. It watches multiple event sources and routes them to the right profile:

| Event Source | What It Detects |
|---|---|
| DRM uevents (`/sys/class/drm/`) | EDID change, connector hotplug, mode change |
| udev USB subsystem | USB device added/removed (for HID init) |
| systemd D-Bus (`org.freedesktop.systemd1`) | Service unit started/stopped (WiVRn, Monado) |
| KWin D-Bus | VR state changes, manual activation from settings UI |
| inotify on `/etc/vr-profiles.d/` | Profile files added/modified at runtime |

New event sources can be added without changing profile format or plugin code.

---

## Activation Flow (Custodian → Plugin)

```
Event fires (EDID change / service appears / user clicks button)
        │
        ▼
Custodian scans all loaded profiles for a match
        │
    match found?
    ┌───┴────┐
   yes       no (+ manual trigger) → activate flat_monitor fallback
    │
    ▼
Custodian executes profile's HID_INIT_PAYLOAD_3D (if any)
        │
        ▼
Custodian starts OpenXR runtime via systemd D-Bus (StartUnit "replace")
        │
        ▼
For Monado: wait for IPC socket to appear in XDG_RUNTIME_DIR
  (socket = "monado_comp_ipc" — created when Monado is ready for connections)
For WiVRn: wait for D-Bus service name to register
        │
        ▼
Custodian notifies KWin plugin via D-Bus:
    requestActivateProfile(profileName, outputName)
        │
        ▼
KWin plugin calls activateForProfile(profile, output)
  - Applies mode via KWin output API
  - Creates Virtual-T
  - Waits for OpenXR compositor window (windowAdded)
  - Pins window to VR output, fullscreens it
  - Sets vrActive = true
        │
        ▼
Plugin calls custodian.vrReady() (informational)
```

Deactivation is the reverse: event fires (mode reverts / service stops / user stops),
custodian notifies plugin via `requestDeactivate()`, plugin tears down and calls
`custodian.vrStopped()`, then custodian stops OpenXR runtime.

---

## Custodian Implementation Notes

These are hard-won invariants from debugging the Xreal Air integration. They apply
to any device that uses USB HID for mode switching.

### Startup Scan Order

`scanConnectors()` **must** run before `scanUsbDevices()`. If the display is already
in SBS mode when the custodian starts, VR activates (`m_active = true`) before USB
scanning runs. `scanUsbDevices()` must check `m_active` and skip the 2D HID init if
VR is already active. Reversing this order causes a startup race:

1. `scanUsbDevices()` sends 2D HID init → device starts switching to desktop mode
2. `scanConnectors()` sees SBS mode → activates VR → sends 3D HID init
3. Monado starts while USB is mid-disconnect (mode-switch causes USB disconnect)
4. Monado doesn't find the USB device → falls back to wrong HMD (simulated, wrong resolution)

### USB Reconnect During HID Mode Switch

Many HID-controlled displays **disconnect and reconnect their USB bus** when switching
display modes. The custodian receives `usbDeviceAdded` events for each reconnect.

`onUsbDeviceAdded` **must not send 2D HID init if VR is already active** for that
device. Failing to guard this causes an infinite reset loop:
- VR activates → send 3D HID → USB disconnect/reconnect
- `onUsbDeviceAdded` fires → send 2D HID (bug) → device reverts to desktop mode
- Result: one eye dark ("half on, half off")

The guard: if `m_active && m_activeProfile->hidVendorId == vendorId`, skip HID init
and log "USB reconnect during active VR session — not resetting HID mode".

### DRM Uevent Gap (Polling Fallback)

Some GPU drivers (notably `i915` on Intel) do **not** generate `CONNECTOR_STATUS`
DRM uevents when a DP-Alt display switches modes via USB HID. The Xreal Air on Intel
HD 520 is a confirmed example — pressing the SBS button sends no DRM uevent at all.

Relying solely on udev DRM events for these devices means VR never activates.

**Fix**: when a USB device matching a display-type profile is added, start a
2-second interval `QTimer` that calls `scanConnectors()` repeatedly. Stop the
timer when VR activates (connector found in SBS mode). Resume polling when VR
deactivates so the next SBS press is caught. Stop immediately if the USB device
is removed.

This is intentionally a polling fallback, not the primary mechanism. Hardware
that generates proper DRM uevents never needs the timer — `onDrmConnectorChanged`
fires immediately and the timer is never started.

### Monado IPC Socket Lifecycle

- Socket path: `$XDG_RUNTIME_DIR/monado_comp_ipc`
- Created by Monado when it is **ready to accept OpenXR connections** (after Vulkan init)
- Monado **never recreates** the socket if it is deleted while running
- Never call `QFile::remove(socketPath)` while an OpenXR session is active
- Before removing a stale socket: check `QFile::exists()` and if present, treat it as
  "Monado already ready" and notify the plugin immediately without deleting it

### EDID Vendor Decoding

The EDID vendor code (bytes 8–9, 3×5-bit encoding) is **not** the same as the USB
vendor name or the brand name printed on the device. Always verify by reading raw
EDID bytes from `/sys/class/drm/<connector>/edid` and decoding them directly.
Do not assume vendor from USB IDs. Example: Xreal Air Gen 1 USB vendor is 0x3318
("Hangzhou Rokid Technology") but EDID vendor is "MRG".

### D-Bus Object Registration for the Plugin

The KWin plugin registers its D-Bus object with:
```cpp
QDBusConnection::ExportAllProperties
| QDBusConnection::ExportAllSignals
| QDBusConnection::ExportScriptableInvokables
```
`ExportScriptableInvokables` is **required** to expose `Q_SCRIPTABLE` methods that are
declared in `public:` (not `public Q_SLOTS:`). Without this flag, methods like
`requestActivateProfile` appear in the source but are invisible on the D-Bus — the
custodian's calls silently succeed (fire-and-forget) but nothing happens.

---

## Shell Scripts — Deprecation Path

Current scripts and their replacement:

| Script | Current Role | Replacement |
|---|---|---|
| `xreal-mode-watch.sh` | Polls DRM, activates VR | `kwin-vr-custodian` |
| `xreal-init.sh` | Sends USB HID 2D command | `HID_INIT_PAYLOAD_2D` in profile, custodian sends it |
| `xreal-sbs-switch.py` | Sends USB HID 3D/2D command | `HID_INIT_PAYLOAD_3D/2D` in profile, custodian sends it |
| `boot-init.sh` | Detects hardware at boot | Custodian startup scan |
| `vr-detect.sh` | Detects VR hardware | Custodian profile matching |

**Target state: zero shell scripts in the activation path.**
udev rules remain only for setting device permissions (`MODE="0666"`), not for logic.

---

## Anti-Patterns (Never Do These)

- `if (output->name() == "DP-1")` — connector names are not stable
- `if (vendor == "xreal")` — use profile EDID match
- Hardcoded resolutions in C++ (`3840`, `1080`) — read from profile
- Shell script detecting mode change and calling D-Bus — custodian owns this
- `kscreen-doctor` in any script — plugin applies modes via KWin API
- Starting Monado from a shell script — custodian starts it via systemd D-Bus
- Adding a new device by editing C++ — add a profile file, zero code changes

---

## Key Invariants

1. **Plugin** is the single source of truth for VR state
2. **Profile files** are the single source of truth for device behavior
3. **Custodian** is the single source of truth for hardware observation
4. Adding a new VR device requires only a new profile file — no code changes
5. All mode/output decisions go through KWin's internal output API
6. The custodian and plugin communicate only via D-Bus — clean boundary
