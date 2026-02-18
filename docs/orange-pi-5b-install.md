# KWin VR on Orange Pi 5B — Full Install Guide

Stereoscopic VR desktop with head tracking on a stock Orange Pi 5B.
Tested with a Samsung Odyssey+ (HDMI, auto-boot VR) and Xreal Air Gen 1
(USB-C DP, SBS button toggle).

---

## Hardware Requirements

- Orange Pi 5B (RK3588S, any RAM size; 16GB recommended for building)
- Active cooling (sustained load during build and VR rendering)
- Headset connected before first boot (or replug before SDDM starts)

---

## 1. Install Base OS

Use [7Ji's Arch Linux ARM image](https://github.com/7Ji/orangepi5-archlinuxarm/releases)
for OPi 5B. Flash to microSD or eMMC:

```bash
# From another machine:
xzcat orangepi5b-archlinuxarm-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot, log in as `alarm` (password: `alarm`). Become root: `su` (password: `root`).

### Initial setup

```bash
# Set up pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Full system update
pacman -Syu

# Install build essentials
pacman -S base-devel git cmake ninja python

# Install desktop
pacman -S plasma-meta sddm konsole
systemctl enable sddm
```

---

## 2. Install Joshua BSP 6.1 Kernel (with Panthor)

The stock OPi BSP 5.10 kernel lacks Panthor (needed for Mesa PanVK Vulkan).
Joshua's 6.1 tree includes a Panthor backport and is the base for our
custom kernel with the dw-dp DisplayPort fix.

```bash
# Add 7Ji's custom repo to /etc/pacman.conf — insert before [core]:
# [7Ji]
# Server = https://github.com/7Ji/archrepo/releases/download/any
# SigLevel = Never

pacman -S linux-aarch64-rockchip-bsp6.1-joshua-git
```

Boot into the Joshua 6.1 kernel to confirm Panthor is present:

```bash
lsmod | grep panthor   # should show panthor module
ls /dev/dri/           # renderD128=rockchip-drm, renderD130=panthor
```

---

## 3. Build Custom Kernel with dw-dp PHY Cycling Fix

The Xreal Air Gen 1 (and similar glasses) fail DP link training at HBR
(2700 MHz) on mode switches. The stock dw-dp driver immediately downgrades
to RBR (1620 MHz), which lacks bandwidth for 3840×1080@60. This kernel
patch adds a PHY power-cycle retry before downgrading.

The Samsung Odyssey+ does not need this patch (HDMI), but building a unified
kernel is simpler.

### 3.1 Clone Joshua's tree

```bash
cd ~
git clone https://github.com/Joshua-Riek/linux-rockchip.git joshua-kernel
cd joshua-kernel
git checkout noble   # 6.1.75 BSP + panthor backport
```

### 3.2 Apply the dw-dp patch

Edit `drivers/gpu/drm/rockchip/dw-dp.c`. Find `dw_dp_link_train_full()`
(search for `clock recovery failed`). Replace the failure block:

```c
// BEFORE (original — immediately downgrades on first failure):
if (!link->train.clock_recovered) {
    dev_err(dp->dev, "clock recovery failed, downgrading link\n");
    /* ... downgrade logic ... */
}

// AFTER — add PHY cycling retry before the downgrade:
if (!link->train.clock_recovered) {
    if (cr_retries < 3) {
        cr_retries++;
        dev_info(dp->dev,
                 "clock recovery failed at %u MHz, PHY cycling + 3s wait (%d/3)\n",
                 link->rate / 100, cr_retries);
        dw_dp_link_train_set_pattern(dp, DP_TRAINING_PATTERN_DISABLE);
        phy_power_off(dp->phy);
        msleep(3000);
        phy_power_on(dp->phy);
        dw_dp_link_power_up(dp);
        goto retry;
    }

    dev_err(dp->dev, "clock recovery failed, downgrading link\n");
    cr_retries = 0;
    /* ... original downgrade logic follows unchanged ... */
}
```

You also need to declare `cr_retries` near the top of the function:

```c
int cr_retries = 0;
```

### 3.3 Build and install

```bash
cd ~/joshua-kernel
make -j$(nproc) Image modules dtbs

# Install modules
sudo make modules_install

# Install kernel — extlinux boots a specific filename, not /boot/Image
sudo cp arch/arm64/boot/Image /boot/vmlinuz-linux-dp-fix
sudo cp arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5b.dtb \
    /boot/dtbs/linux-dp-fix/rockchip/rk3588s-orangepi-5b.dtb
```

### 3.4 Add extlinux entry

Edit `/boot/extlinux/extlinux.conf` and add a new label at the top, then
set it as DEFAULT:

```
DEFAULT linux-dp-fix

LABEL linux-dp-fix
    LINUX /vmlinuz-linux-dp-fix
    INITRD /booster-linux-dp-fix.img
    FDT /dtbs/linux-dp-fix/rockchip/rk3588s-orangepi-5b.dtb
    APPEND root=UUID=<your-uuid> rw
```

Generate the initrd:

```bash
sudo booster build /boot/booster-linux-dp-fix.img --kernel-version $(make -s kernelrelease)
```

Reboot and verify the patch is active:

```bash
dmesg | grep "PHY cycling"
# On Xreal SBS switch you should see:
# dw-dp fde50000.dp: clock recovery failed at 2700 MHz, PHY cycling + 3s wait (1/3)
# dw-dp fde50000.dp: clock recovery succeeded
```

---

## 4. GPU Drivers

### Mesa PanVK (Vulkan via Panthor — required for KWin VR)

The 7Ji repo provides a Mesa build with PanVK enabled. Verify:

```bash
pacman -S mesa
MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1 vulkaninfo 2>/dev/null | grep deviceName
# Should show: Mali-G610
```

If `vulkaninfo` isn't available: `pacman -S vulkan-tools`

### Mali firmware

```bash
pacman -S mali-valhall-g610-firmware
```

---

## 5. Build Dependencies

```bash
pacman -S \
    # KWin build
    extra-cmake-modules kdecoration kglobalaccel kidletime kscreenlocker \
    kwayland-protocols plasma-wayland-protocols libinput libxcvt \
    wayland-protocols xcb-util-cursor xorg-xwayland libdisplay-info libei \
    lcms2 libqaccessibilityclient-qt6 \
    # Qt (system packages — already at 6.10.x on Arch ARM)
    qt6-base qt6-declarative qt6-quick3d qt6-wayland qt6-tools \
    # OpenXR
    openxr \
    # Monado build
    libuvc libusb eigen glslang shaderc \
    # Runtime tools
    kscreen python
```

---

## 6. GL Alpha Fix Shim

Qt 6 on GLES 3.0+ uses `GL_ALPHA` for glyph cache textures, which is
invalid on GLES 3.x. This LD_PRELOAD shim intercepts those calls and
substitutes `GL_R8` with swizzle — fixing blank/missing text in KWin.

The source is in this repo at `extras/gl_alpha_fix.c`.

```bash
# Build the shim
gcc -O2 -shared -fPIC -o /tmp/libgl_alpha_fix.so \
    extras/gl_alpha_fix.c -ldl

sudo cp /tmp/libgl_alpha_fix.so /usr/lib/libgl_alpha_fix.so
```

This is loaded automatically by `vr-env.sh` via `LD_PRELOAD` for the
Plasma session when a VR headset is detected.

---

## 7. Build Monado

Monado is the OpenXR runtime. We build from source because several patches
are needed for GLES/DMA-BUF compatibility on Panthor.

### 7.1 Clone

```bash
mkdir -p ~/vr-build && cd ~/vr-build
git clone https://gitlab.freedesktop.org/monado/monado.git
cd monado
```

### 7.2 Apply patches

#### Patch 1 — DMA-BUF export handle type (`src/xrt/auxiliary/vk/vk_image_allocator.c`)

Change the VkExternalMemoryHandleTypeFlagBits from OPAQUE_FD to DMA_BUF:

```c
// In get_image_memory_handle_type() and image creation:
// Change: VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT
// To:     VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT
// Also force VK_IMAGE_TILING_LINEAR when using DMA_BUF handle type
```

#### Patch 2 — DMA-BUF FD export (`src/xrt/auxiliary/vk/vk_helpers.c`)

```c
// In get_device_memory_handle():
// Change handleType to VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT
```

#### Patch 3 — DRM format fix (`src/xrt/compositor/client/comp_gl_eglimage_swapchain.c`)

On little-endian ARM, `VK_FORMAT_R8G8B8A8` byte order maps to
`DRM_FORMAT_ABGR8888`, not `DRM_FORMAT_RGBA8888`:

```c
// Change: DRM_FORMAT_RGBA8888
// To:     DRM_FORMAT_ABGR8888
// (for GL_RGBA8 and GL_SRGB8_ALPHA8 formats)
```

#### Patch 4 — Depth format fallback (same file)

Depth/stencil formats have no DRM FOURCC — use `glTexImage2D` local
allocation instead of EGL import for those formats:

```c
// For GL_DEPTH24_STENCIL8 / GL_DEPTH_COMPONENT etc:
// Fall through to glTexImage2D local alloc, skip EGL path
```

#### Patch 5 — 64-byte pitch alignment (same file)

Panthor requires 64-byte aligned pitch for DMA-BUF import:

```c
// After: row_pitch = width * bytes_per_pixel
// Add:   row_pitch = (row_pitch + 63) & ~63;
```

#### Patch 6 — WMR camera null check (`src/xrt/drivers/wmr/wmr_source.c`)

Prevents segfault when camera open fails during WMR cleanup:

```c
// In wmr_source_stream_stop():
// Add null check: if (ws->camera) { wmr_camera_stop(ws->camera); }
```

#### Patch 7 — Wayland compositor window size (`src/xrt/compositor/main/comp_settings.c`)

Xreal Air SBS needs the full 3840×1080 window, not halved:

```c
// Remove the /2 divisor for Wayland forced mode width
```

#### Patch 8 — No auto-SBS mode switch (`src/xrt/drivers/xreal_air/xreal_air_hmd.c`)

Forcing SBS mode during Monado init triggers DP link retraining that
races with KWin startup:

```c
// Remove or comment out:
// switch_display_mode(hmd, XREAL_AIR_DISPLAY_MODE_3D);
// Use current mode instead (glasses start in 2D, user switches manually)
```

### 7.3 Build

```bash
cd ~/vr-build/monado
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DXRT_FEATURE_WINDOW_PEEK=OFF \
    -DXRT_FEATURE_SLAM=ON

ninja -C build -j$(nproc)
```

### 7.4 Install

`ninja install` may produce 0-byte binaries — always verify:

```bash
sudo ninja -C build install

# Verify sizes — if 0 bytes, copy manually:
ls -la /usr/bin/monado-service /usr/lib/libmonado.so.25.1.0
sudo cp build/src/xrt/targets/service/monado-service /usr/bin/monado-service
sudo cp build/src/xrt/targets/libmonado/libmonado.so.25.1.0 /usr/lib/libmonado.so.25.1.0
```

### 7.5 OpenXR runtime symlink

```bash
sudo mkdir -p /etc/xdg/openxr/1
sudo ln -sf /usr/share/openxr/1/openxr_monado.json \
    /etc/xdg/openxr/1/active_runtime.json
```

---

## 8. Build KWin VR

### 8.1 Clone

```bash
cd ~/vr-build
git clone git@github.com:Bake-Ware/kwin-vr.git
cd kwin-vr
git checkout 6.5.5_vr
```

### 8.2 Build

```bash
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

ninja -C build -j$(nproc)
```

> Build takes ~20–30 minutes on an OPi 5B with 16GB RAM.
> Watch thermals — `watch -n2 cat /sys/class/thermal/thermal_zone0/temp`

### 8.3 Install

```bash
sudo ninja -C build install
```

This replaces the system KWin. Do NOT restart KWin via systemctl after
installing — it causes a DRM crash loop requiring a hard reboot. Always
reboot cleanly to load the new build.

---

## 9. System Configuration

### 9.1 SDDM auto-login and Wayland mode

Create `/etc/sddm.conf.d/autologin.conf`:

```ini
[Autologin]
User=alarm
Session=plasma

[General]
DisplayServer=wayland
```

### 9.2 Disable screen locking

Prevents KWin restarts from triggering the lock screen:

```bash
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
```

### 9.3 udev rules

**`/etc/udev/rules.d/99-wmr-headset.rules`** (Samsung Odyssey+):
```
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="0659", MODE="0666"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="7312", MODE="0666"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="7084", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="045e", ATTR{idProduct}=="0659", MODE="0666"
```

**`/etc/udev/rules.d/98-wmr-hololens-config.rules`** (force USB config):
```
ACTION=="add", ATTR{idVendor}=="045e", ATTR{idProduct}=="0659", ATTR{bConfigurationValue}!="1", ATTR{bConfigurationValue}="1"
```

**`/etc/udev/rules.d/70-xreal-air.rules`** (Xreal Air Gen 1):
```
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3318", ATTRS{idProduct}=="0424", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="3318", ATTRS{idProduct}=="0424", MODE="0666"
```

```bash
sudo udevadm control --reload-rules
```

### 9.4 VR profiles

Create `/etc/vr-profiles.d/` and add one conf file per headset.

**`/etc/vr-profiles.d/samsung-odyssey-plus.conf`**:
```bash
VR_NAME="Samsung Odyssey+"
VR_DETECT_USB="045e:0659"
VR_DISPLAY_CONNECTOR="HDMI-A-1"
VR_WIDTH=2880
VR_HEIGHT=1600
VR_REFRESH=90
VR_SCALE=1
VR_OPENXR_RUNTIME="monado"
VR_BOOT_INIT="/usr/lib/vr-headset-init/wmr-init.sh"
VR_AUTO_START=true
```

**`/etc/vr-profiles.d/xreal-air-gen1.conf`**:
```bash
VR_NAME="Xreal Air Gen 1"
VR_DETECT_USB="3318:0424"
VR_DISPLAY_CONNECTOR="DP-1"
VR_WIDTH=1920
VR_HEIGHT=1080
VR_REFRESH=60
VR_SCALE=1
VR_OPENXR_RUNTIME="monado"
VR_BOOT_INIT="/usr/lib/vr-headset-init/xreal-init.sh"
VR_AUTO_START=false
```

### 9.5 VR detection and init scripts

Install scripts to `/usr/lib/vr-headset-init/`. All are in this repo under `extras/vr-headset-init/`.

**`vr-detect.sh`** — scans USB sysfs for VID:PID matches:
```bash
#!/bin/bash
for profile in /etc/vr-profiles.d/*.conf; do
    [ -f "$profile" ] || continue
    VR_DETECT_USB=""
    source "$profile"
    [ -z "$VR_DETECT_USB" ] && continue
    IFS=: read vid pid <<< "$VR_DETECT_USB"
    for dev in /sys/bus/usb/devices/*/idVendor; do
        [ -f "$dev" ] || continue
        devdir=$(dirname "$dev")
        if [ "$(cat "$devdir/idVendor" 2>/dev/null)" = "$vid" ] && \
           [ "$(cat "$devdir/idProduct" 2>/dev/null)" = "$pid" ]; then
            echo "$profile"
            exit 0
        fi
    done
done
exit 1
```

**`boot-init.sh`** — retries detection up to 5 seconds (USB enum race):
```bash
#!/bin/bash
PROFILE=""
for i in $(seq 1 10); do
    PROFILE=$(/usr/lib/vr-headset-init/vr-detect.sh 2>/dev/null)
    [ $? -eq 0 ] && break
    PROFILE=""
    sleep 0.5
done

if [ -z "$PROFILE" ]; then
    echo "none" > /run/vr-detected
    exit 0
fi

source "$PROFILE"
echo "$PROFILE" > /run/vr-detected
chmod 644 /run/vr-detected
echo "Detected: $VR_NAME"

if [ -n "$VR_BOOT_INIT" ] && [ -x "$VR_BOOT_INIT" ]; then
    "$VR_BOOT_INIT"
fi
```

**`wmr-init.sh`** — Samsung Odyssey+ boot init:
```bash
#!/bin/bash
echo 1 > /sys/bus/usb/devices/2-1.1/bConfigurationValue 2>/dev/null
chmod 666 /dev/hidraw3 /dev/hidraw4 /dev/bus/usb/002/003 2>/dev/null
sleep 1
python3 /usr/lib/vr-headset-init/wmr-screen-on.py
```

**`wmr-screen-on.py`** — sends HID screen-enable command to the headset:

```python
#!/usr/bin/env python3
import os, glob, time

def find_hidraw(vid, pid):
    for dev in glob.glob('/sys/class/hidraw/hidraw*/device/uevent'):
        with open(dev) as f:
            content = f.read()
        if f'{vid:04X}' in content and f'{pid:04X}' in content:
            return '/dev/' + dev.split('/')[4]
    return None

hidraw = find_hidraw(0x04e8, 0x7312)   # Samsung companion device
if not hidraw:
    print("Samsung Odyssey control device not found")
    exit(1)

with open(hidraw, 'wb') as f:
    f.write(bytes([0x12, 0x01]))        # screen-on command

time.sleep(4)                           # wait for HDMI to enumerate
with open('/sys/class/drm/card0-HDMI-A-1/status') as f:
    print(f"HDMI-A-1: {f.read().strip()}")
```

**`xreal-init.sh`** — Xreal Air boot init:
```bash
#!/bin/bash
chmod 666 /dev/hidraw* 2>/dev/null
```

**`xreal-mode-watch.sh`** — watches for SBS button press (see full script in `extras/`).

Mark all scripts executable:
```bash
sudo chmod +x /usr/lib/vr-headset-init/*.sh
sudo chmod +x /usr/lib/vr-headset-init/*.py
```

### 9.6 Boot init system service

**`/etc/systemd/system/vr-headset-init.service`**:
```ini
[Unit]
Description=VR Headset Hardware Init
After=systemd-udevd.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/lib/vr-headset-init/boot-init.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

```bash
sudo systemctl enable vr-headset-init.service
```

### 9.7 Session environment script

This runs before KWin starts in every Plasma session. It reads
`/run/vr-detected`, sets `KWIN_FORCE_DESKTOP_OUTPUTS`, configures the
OpenXR runtime, writes `~/.config/kwinvr`, and enables/disables the
mode-watch service as appropriate.

**`~/.config/plasma-workspace/env/vr-env.sh`**:
```bash
#!/bin/bash
DETECTED=$(cat /run/vr-detected 2>/dev/null)
if [ -z "$DETECTED" ] || [ "$DETECTED" = "none" ]; then
    unset KWIN_FORCE_DESKTOP_OUTPUTS
    exit 0
fi

source "$DETECTED"

# GL_ALPHA fix shim — fixes blank text on GLES 3.x
export LD_PRELOAD="/usr/lib/libgl_alpha_fix.so${LD_PRELOAD:+:$LD_PRELOAD}"

if [ -n "$VR_DISPLAY_CONNECTOR" ]; then
    export KWIN_FORCE_DESKTOP_OUTPUTS="$VR_DISPLAY_CONNECTOR"
fi

if [ "$VR_OPENXR_RUNTIME" != "wivrn" ]; then
    export XR_RUNTIME_JSON="/usr/share/openxr/1/openxr_monado.json"
fi

AUTO_START="${VR_AUTO_START:-true}"
KWINVR_CFG="$HOME/.config/kwinvr"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key xrTestEnabled false
kwriteconfig6 --file "$KWINVR_CFG" --group General --key autoStart "$AUTO_START"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key width "$VR_WIDTH"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key height "$VR_HEIGHT"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key scale "$VR_SCALE"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key refreshrate "$VR_REFRESH"

# Enable mode-watch for headsets with button-toggle VR (e.g. Xreal Air)
if [ "$VR_AUTO_START" = "false" ]; then
    systemctl --user enable --now xreal-mode-watch.service 2>/dev/null || true
else
    systemctl --user disable --now xreal-mode-watch.service 2>/dev/null || true
fi
```

```bash
chmod +x ~/.config/plasma-workspace/env/vr-env.sh
```

### 9.8 Monado user service

**`~/.config/systemd/user/monado.service`**:
```ini
[Unit]
Description=Monado OpenXR Runtime Service
After=graphical-session.target

[Service]
Type=simple
StandardInput=null
Environment=XRT_NO_STDIN=1
Environment=XRT_COMPOSITOR_FORCE_WAYLAND=1
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WMR_SLAM=false
ExecStart=/usr/bin/monado-service
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user enable monado.service
```

### 9.9 Xreal mode-watch user service

**`~/.config/systemd/user/xreal-mode-watch.service`**:
```ini
[Unit]
Description=Xreal Air Mode Watch (auto-activate VR on SBS switch)
After=graphical-session.target

[Service]
Type=simple
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/lib/vr-headset-init/xreal-mode-watch.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

This service is started/stopped dynamically by `vr-env.sh` — don't
`systemctl --user enable` it manually.

---

## 10. Headset-Specific Notes

### Samsung Odyssey+ (WMR)

The headset EDID reports `non-desktop=1`, which normally causes KWin to
skip it. Our KWin patch overrides this when the connector is listed in
`KWIN_FORCE_DESKTOP_OUTPUTS` (set by `vr-env.sh`).

The HoloLens Sensors USB device (VID 045e PID 0659) provides IMU and
camera data. It boots in configuration 0 with non-standard interface
numbering. The udev rule forces configuration 1 at plug-in. Monado is
built with `WMR_SLAM=false` — 3DOF IMU tracking only.

HDMI must be powered on before KWin starts. The `wmr-init.sh` script
sends the screen-on HID command and waits 4 seconds for HDMI-A-1 to
appear, before SDDM launches KWin.

VR auto-activates 15 seconds after session start (`autoStart=true`
in `~/.config/kwinvr`).

### Xreal Air Gen 1

Connected via USB-C DP-alt (USB VID 3318 PID 0424). Boots in 2D mode
(1920×1080). The physical SBS button on the glasses switches to 3840×1080
SBS mode, which triggers the `xreal-mode-watch.sh` daemon to activate VR.

The Gen 1 EDID advertises 120Hz as the preferred mode but cannot reliably
drive it over this DP link — the mode-watch forces 60Hz on every
2D transition and at startup.

When SBS is pressed:
1. Glasses fire HPD (disconnect/reconnect)
2. Kernel retries HBR link training; PHY cycling patch enables recovery
3. Mode-watch detects `3840x1080` in `/sys/class/drm/card0-DP-1/modes`
4. Mode-watch calls kscreen-doctor to commit the mode (triggers full modeset)
5. Monado restarts to pick up the new resolution
6. VR activates via D-Bus

If glasses get stuck disconnected after SBS press: physical replug resets
their DP receiver.

---

## 11. KWin Window Rule for Monado

Monado's Wayland surface needs to be sent fullscreen to the headset output,
and hidden from the VR scene. Add to `~/.config/kwinrulesrc`:

```ini
[General]
count=1
rules=1

[1]
Description=Monado VR window to headset fullscreen
clientmachine=localhost
clientmachinematch=0
wmclass=openxr/monado-service
wmclasscomplete=false
wmclassmatch=1
screen=0
screenrule=3
fullscreen=true
fullscreenrule=3
```

> **Note:** The `screen=0` index can shift after KWin restarts. Verify
> with `kscreen-doctor -o` and update if the headset output changes index.

The Monado window filter in our KWin patch (`windowmodelfilter.cpp`)
already excludes `resourceClass == "openxr"` from the VR scene, preventing
the infinite mirror effect.

---

## 12. Quick Reference

| Action | Command |
|--------|---------|
| Activate VR | `Ctrl+Meta+J` |
| Activate VR (D-Bus) | `dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr org.freedesktop.DBus.Properties.Set string:org.kde.kwinvr string:vrActive variant:boolean:true` |
| Deactivate VR | Same with `boolean:false` |
| Check VR state | `dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr org.freedesktop.DBus.Properties.Get string:org.kde.kwinvr string:vrActive` |
| Check outputs | `kscreen-doctor -o` |
| Restart Monado | `systemctl --user restart monado.service` |
| Check detection | `cat /run/vr-detected` |
| Rebuild VR plugin | `ninja -C ~/vr-build/kwin-vr/build vr && sudo cp ~/vr-build/kwin-vr/build/bin/kwin/plugins/vr.so /usr/lib/qt6/plugins/kwin/plugins/vr.so` then reboot |
| Rebuild Monado | `ninja -C ~/vr-build/monado/build && sudo cp ~/vr-build/monado/build/src/xrt/targets/service/monado-service /usr/bin/monado-service` |
| Check DP link | `dmesg \| grep -E "(dw-dp\|PHY cycling\|clock recovery)"` |

---

## 13. Critical Gotchas

1. **KConfig file name**: `kcfg name="kwinvr"` reads `~/.config/kwinvr`
   — NOT `~/.config/kwinvrrc`. The trailing `rc` is not added for this plugin.

2. **Never restart KWin via systemctl**: `systemctl --user restart plasma-kwin_wayland`
   causes a DRM crash loop. Reboot the machine instead.

3. **Kernel install path**: extlinux boots `/boot/vmlinuz-linux-dp-fix`,
   NOT `/boot/Image`. Always copy to the right filename.

4. **Monado `ninja install` 0-byte binaries**: Known issue. Always
   `ls -la` the installed binaries and copy from the build tree if 0 bytes.

5. **HDMI must exist before KWin starts**: For Samsung Odyssey+, the
   `wmr-init.sh` must complete (HDMI-A-1 connected) before SDDM launches.
   If KWin starts without the headset on HDMI, it won't detect it until reboot.

6. **USB enumeration race**: `vr-headset-init.service` retries USB detection
   for 5 seconds. If the headset takes longer than that to enumerate, the
   detection writes "none" and VR won't auto-start. Replug or reboot with
   headset connected and powered.

7. **Xreal Air 120Hz**: The Gen 1 advertises 120Hz in EDID but can't drive
   it reliably. The mode-watch forces 60Hz — do not override this.

8. **Never unbind dw-dp**: `echo fde50000.dp > /sys/bus/platform/drivers/dw-dp/unbind`
   destroys the entire rockchip-drm card0 (hard hang, requires power cycle).

9. **Panthor render node**: KWin and Monado must use `renderD130` (panthor)
   for Vulkan, not `renderD128` (rockchip-drm). Set `DRI_PRIME=pci-0000_00_00_0`
   or use the Vulkan device selector if multiple devices are exposed.
