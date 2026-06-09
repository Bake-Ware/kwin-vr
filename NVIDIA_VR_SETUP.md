# KWin-VR: NVIDIA + Xreal Air Setup Guide

This documents the exact steps to get VR mode working on the upstream `6.6.3_vr` branch with an NVIDIA GPU and Xreal Air glasses via USB-C DP-alt.

Tested on: RTX 2070, NVIDIA driver 590.x, CachyOS (Arch-based), Monado v25.1.0, Qt 6.10+

## Architecture

The upstream `6.6.3_vr` branch uses **DRM leasing** (not the custodian service from `6.5.5_vr`). The flow is:

1. KWin marks the glasses output as **leasable** (auto-detected by EDID)
2. Monado starts in **Wayland DRM lease mode** and requests a lease from KWin
3. KWin grants the lease — Monado now owns the glasses display
4. VR mode is activated via shortcut (`Ctrl+Meta+J`) or D-Bus

## Prerequisites

- Monado installed (`monado-service` binary at `/usr/bin/monado-service`)
- OpenXR loader installed (`libopenxr_loader.so`)
- Monado's Xreal Air driver compiled in (check `monado-service` lists `xreal_air` builder)
- Qt6 Quick3DXr module installed

## Step 1: OpenXR Runtime JSON

The system default at `/etc/xdg/openxr/1/active_runtime.json` may point to WiVRn or another runtime. The KWin VR plugin has its own setting to override this.

Set it to Monado:

```bash
kwriteconfig6 --file kwinvr --group General --key openXrRuntimeJson /usr/share/openxr/1/openxr_monado.json
```

Verify:
```bash
grep openXrRuntimeJson ~/.config/kwinvr
# Should show: openXrRuntimeJson=/usr/share/openxr/1/openxr_monado.json
```

**WARNING**: The KCM settings panel may wipe this key if you save settings. Re-add it after using the settings UI.

## Step 2: Monado Systemd Service

Create/edit `~/.config/systemd/user/monado.service`:

```ini
[Unit]
Description=Monado OpenXR Runtime
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/monado-service
Restart=on-failure
RestartSec=3
TimeoutStopSec=5
KillMode=mixed

# CRITICAL: Use Wayland DRM lease mode
# This selects the "direct_wayland" compositor target in Monado,
# which uses the wp_drm_lease_v1 Wayland protocol to get a DRM lease
# from KWin for the glasses display.
Environment=XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT=1

Environment=XRT_NO_STDIN=1
Environment=WMR_SLAM=false

# NVIDIA-specific
Environment=XRT_COMPOSITOR_COMPUTE=false
Environment=XRT_COMPOSITOR_FORCE_GPU_INDEX=0
Environment=GBM_BACKEND=nvidia-drm
Environment=__GLX_VENDOR_LIBRARY_NAME=nvidia
```

Key environment variables explained:

| Variable | Value | Why |
|----------|-------|-----|
| `XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT` | `1` | Selects `direct_wayland` target = DRM lease mode. **This is the correct one.** |
| `XRT_COMPOSITOR_FORCE_WAYLAND` | (DO NOT USE) | Selects `wayland` target = regular Wayland surface. Shows a black rectangle on your monitor instead of driving the glasses. |
| `XRT_COMPOSITOR_FORCE_XCB` | (DO NOT USE) | Old custodian-era workaround. Forces X11 compositing, incompatible with DRM leasing. |
| `XRT_COMPOSITOR_COMPUTE` | `false` | Disables compute compositor on NVIDIA |
| `XRT_COMPOSITOR_FORCE_GPU_INDEX` | `0` | Pin to primary GPU |
| `TimeoutStopSec` | `5` | Monado ignores SIGTERM when holding a Vulkan/DRM session. Without this, systemd waits 90 seconds on logout before SIGKILL. |
| `KillMode` | `mixed` | SIGTERM main process, SIGKILL children after timeout |

After creating/editing:
```bash
systemctl --user daemon-reload
```

## Step 3: Disable the Custodian (if present)

If you previously used the `6.5.5_vr` branch with the custodian service:

```bash
systemctl --user stop kwin-vr-custodian
systemctl --user disable kwin-vr-custodian
systemctl --user mask kwin-vr-custodian
```

The custodian calls `requestActivateProfile()` which doesn't exist on the upstream plugin and causes D-Bus errors.

## Step 4: Monado Config

Monado's config at `~/.config/monado/config_v0.json` does **NOT** control device builder selection. The only valid `active` values are `"none"`, `"tracking"`, and `"remote"`. There is no way to force the `xreal_air` builder via config.

Builder selection is automatic: if the Xreal Air USB device (VID `3318`) is present, the `xreal_air` builder claims it with `estimate->certain.head = true`.

## Step 5: USB Device Must Be Present

The Xreal Air glasses expose both a display (via DP-alt) and USB HID interfaces. Monado's `xreal_air` builder probes for the USB device by VID:PID.

**Known issue**: When the glasses switch display modes (2D <-> SBS), the USB device may temporarily disappear. If Monado starts while USB is gone, it falls back to "Simulated HMD".

**Fix**: Unplug and replug the glasses, then start Monado. Verify USB is present:
```bash
lsusb | grep 3318
# Should show: Bus XXX Device XXX: ID 3318:0424 Vendor Air
```

## Step 6: Verify Leasable Output

Check that KWin sees the glasses and marks them leasable:

```bash
qdbus6 org.kde.kwinvr /KwinVr org.kde.kwinvr.leasableOutputs
```

Expected output (glasses show as leasable):
```
leasable: true
leased: false
manufacturer: Nreal
model: Air
name: Unknown-2
```

The glasses typically appear as `Unknown-2` on NVIDIA USB-C DP-alt connectors because the EDID vendor/model can be read but the connector name is not recognized.

## Step 7: Start Monado

```bash
systemctl --user start monado.service
```

Verify it selected the Xreal Air builder and got a DRM lease:
```bash
journalctl --user -u monado.service --since="-10s" --no-pager | grep -E "Selected|Using builder|vblank|DRM"
```

Expected:
```
Selected xreal_air because it was certain it could create a head
Using builder xreal_air: Xreal Air
Using DRM node /dev/dri/card1
Started vblank event thread!
```

If you see "Simulated HMD" instead, the USB device is missing (see Step 5).

## Step 8: Activate VR Mode

Via D-Bus:
```bash
qdbus6 org.kde.kwinvr /KwinVr org.freedesktop.DBus.Properties.Set org.kde.kwinvr vrActive true
```

Or via keyboard shortcut: `Ctrl+Meta+J`

Verify:
```bash
qdbus6 org.kde.kwinvr /KwinVr org.kde.kwinvr.vrActive
# Should return: true
```

## Troubleshooting

### KWin crashes on VR activation (SIGSEGV in VrPicking.qml / rayPickAll)

The VrPicking.qml component calls `xrView.rayPickAll()` during QML initialization before the XR session is established. If `xrCreateInstance` fails (wrong runtime, Monado not running), this segfaults.

**Fix**: Ensure Monado is running and healthy BEFORE activating VR mode. Check `journalctl --user -u monado.service` for errors.

### "Failed to connect to socket /run/user/1000/wivrn/comp_ipc"

The OpenXR loader is using WiVRn's runtime JSON instead of Monado's. Fix: set `openXrRuntimeJson` in kwinvr config (Step 1).

### "Atomic modeset test failed! Invalid argument"

NVIDIA DRM atomic modeset issue. Usually non-fatal — VR may still work. If it causes a hang, check NVIDIA driver version.

### Black rectangle on monitor instead of glasses

You're using `XRT_COMPOSITOR_FORCE_WAYLAND` instead of `XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT`. The former creates a regular Wayland window; the latter uses DRM leasing.

### 90-second delay on logout

Monado doesn't handle SIGTERM cleanly. Add `TimeoutStopSec=5` and `KillMode=mixed` to the service file (see Step 2).

### Monado shows "No builder selected in config"

This is normal — config doesn't control builder selection. The line that matters is the next one: "Selected xreal_air because it was certain..." If it says "Selected legacy" instead, the USB device isn't found.

## Quick Start (TL;DR)

```bash
# 1. Set OpenXR runtime
kwriteconfig6 --file kwinvr --group General --key openXrRuntimeJson /usr/share/openxr/1/openxr_monado.json

# 2. Create monado service (see Step 2 for full file)
# Key: XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT=1, TimeoutStopSec=5

# 3. Plug in glasses, verify USB
lsusb | grep 3318

# 4. Start Monado
systemctl --user daemon-reload
systemctl --user start monado.service

# 5. Verify xreal_air builder selected
journalctl --user -u monado.service --since="-5s" | grep Selected

# 6. Activate VR
qdbus6 org.kde.kwinvr /KwinVr org.freedesktop.DBus.Properties.Set org.kde.kwinvr vrActive true
```
