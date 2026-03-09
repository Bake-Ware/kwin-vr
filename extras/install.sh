#!/usr/bin/env bash
# kwin-vr install.sh — Deploy KWin VR stack from pre-built artifacts
#
# Run this on any CachyOS system after building with rebuild-kwin-vr.sh,
# or after cloning build artifacts from another machine.
#
# Usage:
#   ./install.sh             # Uses ~/kwin-vr-build as BUILD_DIR
#   ./install.sh /path/dir   # Uses custom BUILD_DIR
#
# What this script installs:
#   - RPATH-patched KWin VR binary + libraries (in-place in build dir)
#   - Custodian daemon → /usr/lib/kwin-vr-custodian
#   - System-level service files → /usr/lib/systemd/user/
#   - Wayland session entry → /usr/share/wayland-sessions/plasma-vr.desktop
#   - VR hardware profiles → /etc/vr-profiles.d/
#   - Udev rules → /usr/lib/udev/rules.d/70-kwin-vr.rules
#   - Monado patch + rebuild (idempotent)
#   - User systemd services + wrapper scripts
#   - kwin_wayland symlink in BUILD_DIR

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

BUILD_DIR="${1:-$HOME/kwin-vr-build}"
QT_INSTALL="$BUILD_DIR/qt-install"
KDE_INSTALL="$BUILD_DIR/kde-install"
KWIN_INSTALL="$BUILD_DIR/kwin-install"
XWAYLAND_INSTALL="$BUILD_DIR/xwayland-install"
MONADO_PATCHES="$BUILD_DIR/monado-patches"
REPO_DIR="$BUILD_DIR/kwin-vr"
EXTRAS_DIR="$REPO_DIR/extras"

# Canonical RPATH for all VR binaries and libraries.
# Must be RPATH (not RUNPATH) so transitive deps resolve correctly.
VR_RPATH="$KWIN_INSTALL/usr/lib:$QT_INSTALL/lib:$KDE_INSTALL/lib"

###############################################################################
# Helpers
###############################################################################

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()    { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
err()     { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*"; }
section() { echo -e "\n${CYAN}══════════ $* ══════════${NC}\n"; }
die()     { err "$*"; exit 1; }

need_cmd() { command -v "$1" &>/dev/null || die "Required command not found: $1"; }
need_dir() { [ -d "$1" ] || die "Required directory not found: $1 — run rebuild-kwin-vr.sh first"; }

###############################################################################
# Step 0: Preflight checks
###############################################################################
preflight() {
    section "Preflight checks"

    need_cmd patchelf
    need_cmd ninja
    need_cmd cmake
    need_cmd systemctl
    need_cmd paru

    need_dir "$QT_INSTALL"
    need_dir "$KWIN_INSTALL"
    need_dir "$KDE_INSTALL"
    need_dir "$REPO_DIR"
    need_dir "$EXTRAS_DIR"
    need_dir "$MONADO_PATCHES"

    local kwin_bin="$KWIN_INSTALL/usr/bin/kwin_wayland"
    [ -f "$kwin_bin" ] || die "kwin_wayland binary not found at $kwin_bin"

    local vr_so
    vr_so=$(find "$KWIN_INSTALL" -name "vr.so" 2>/dev/null | head -1)
    [ -n "$vr_so" ] || die "vr.so plugin not found in $KWIN_INSTALL"

    log "All preflight checks passed"
    log "BUILD_DIR:      $BUILD_DIR"
    log "USER:           $USER"
    log "HOME:           $HOME"
}

###############################################################################
# Step 1: Fix RPATH on all VR binaries and libraries
###############################################################################
fix_rpath() {
    section "Fixing RPATH on VR binaries and libraries"

    local patched=0
    local failed=0

    # Find all ELF binaries and shared libs in the VR install tree
    while IFS= read -r -d '' f; do
        local type
        type=$(file -b "$f" 2>/dev/null) || continue

        # Skip non-ELF files
        echo "$type" | grep -qE "^ELF" || continue

        # Skip static libs
        echo "$type" | grep -q "shared object\|pie executable\|dynamically linked" || continue

        if patchelf --force-rpath --set-rpath "$VR_RPATH" "$f" 2>/dev/null; then
            patched=$((patched + 1))
        else
            warn "patchelf failed on: $f"
            failed=$((failed + 1))
        fi
    done < <(find "$KWIN_INSTALL" \( -name "*.so" -o -name "*.so.*" -o -type f -executable \) -print0 2>/dev/null)

    log "RPATH patched: $patched files"
    [ "$failed" -gt 0 ] && warn "$failed files could not be patched"

    # Verify the main binary
    local actual_rpath
    actual_rpath=$(patchelf --print-rpath "$KWIN_INSTALL/usr/bin/kwin_wayland" 2>/dev/null)
    log "kwin_wayland RPATH: $actual_rpath"
}

###############################################################################
# Step 2: Create kwin_wayland symlink in BUILD_DIR
###############################################################################
setup_symlink() {
    section "Setting up kwin_wayland PATH symlink"

    local target="$KWIN_INSTALL/usr/bin/kwin_wayland"
    local link="$BUILD_DIR/kwin_wayland"

    if [ -L "$link" ]; then
        rm -f "$link"
    fi
    ln -s "$target" "$link"
    log "Symlink: $link → $target"
}

###############################################################################
# Step 3: Install system files (requires sudo)
###############################################################################
install_system_files() {
    section "Installing system files (sudo required)"

    # ── Custodian binary ──────────────────────────────────────────────────────
    local custodian_src
    # Check kwin-install first, fall back to build dir (cmake puts it in build/bin/)
    custodian_src=$(find "$KWIN_INSTALL" "$REPO_DIR/build" -name "kwin-vr-custodian" -type f 2>/dev/null | head -1)
    [ -n "$custodian_src" ] || die "kwin-vr-custodian binary not found in $KWIN_INSTALL or $REPO_DIR/build"

    sudo install -Dm755 "$custodian_src" /usr/lib/kwin-vr-custodian
    log "Installed: /usr/lib/kwin-vr-custodian"

    # ── System-level systemd user service files ───────────────────────────────
    _write_system_service_custodian
    _write_system_service_monado
    _write_system_socket_monado
    sudo systemctl daemon-reload
    log "Reloaded systemd"

    # ── Wayland session entry ─────────────────────────────────────────────────
    sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/plasma-vr.desktop << EOF
[Desktop Entry]
Exec=/usr/lib/plasma-dbus-run-session-if-needed $BUILD_DIR/startplasma-vr.sh
DesktopNames=KDE
Name=Plasma VR (Wayland)
Comment=Plasma desktop with VR-enabled KWin (OpenXR)
X-KDE-PluginInfo-Version=6.5.5
Type=Application
EOF
    log "Installed: /usr/share/wayland-sessions/plasma-vr.desktop"

    # ── VR hardware profiles ──────────────────────────────────────────────────
    sudo install -d /etc/vr-profiles.d
    _write_profile_xreal_air
    _write_profile_quest3_wivrn
    _write_profile_samsung_odyssey
    log "Installed: /etc/vr-profiles.d/*"

    # ── Udev rules ────────────────────────────────────────────────────────────
    sudo install -Dm644 /dev/stdin /usr/lib/udev/rules.d/70-kwin-vr.rules << 'EOF'
# kwin-vr — VR headset device permissions
# TAG+="uaccess" grants the active seat user access via logind ACLs.
# No world-writable MODE="0666" needed.

# Xreal Air Gen 1 (VID 3318, PID 0424)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3318", ATTRS{idProduct}=="0424", TAG+="uaccess"
SUBSYSTEM=="usb",    ATTRS{idVendor}=="3318", ATTRS{idProduct}=="0424", TAG+="uaccess"
EOF
    sudo udevadm control --reload-rules
    log "Installed: /usr/lib/udev/rules.d/70-kwin-vr.rules"

    # ── Mask xr-driver at system level ───────────────────────────────────────
    # xr-driver grabs Xreal Air HID interfaces before the kernel usbhid driver
    # can create hidraw nodes. Monado needs those nodes.
    # We re-bind via startplasma-vr.sh at session start.
    sudo systemctl --global mask xr-driver.service 2>/dev/null || true
    log "Masked xr-driver.service globally"
}

_write_system_service_custodian() {
    sudo install -Dm644 /dev/stdin /usr/lib/systemd/user/kwin-vr-custodian.service << 'EOF'
[Unit]
Description=kwin-vr Custodian — VR hardware observer and event router
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/lib/kwin-vr-custodian
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
}

_write_system_service_monado() {
    sudo install -Dm644 /dev/stdin /usr/lib/systemd/user/monado.service << 'EOF'
[Unit]
Description=Monado OpenXR Runtime
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/monado-service
Restart=on-failure
RestartSec=3

# Wayland compositor mode — Monado creates a Wayland surface rather than owning
# the display directly. XDG_RUNTIME_DIR and WAYLAND_DISPLAY are inherited from
# the user session environment; do not hardcode them here.
Environment=XRT_COMPOSITOR_FORCE_WAYLAND=1
Environment=XRT_COMPOSITOR_XCB_FULLSCREEN=1
Environment=XRT_NO_STDIN=1
Environment=WMR_SLAM=false
EOF
}

_write_system_socket_monado() {
    sudo install -Dm644 /dev/stdin /usr/lib/systemd/user/monado.socket << 'EOF'
[Unit]
Description=Monado XR service module connection socket
ConditionUser=!root
Conflicts=monado-dev.socket

[Socket]
ListenStream=%t/monado_comp_ipc
RemoveOnStop=true
FlushPending=true

[Install]
WantedBy=sockets.target
EOF
}

_write_profile_xreal_air() {
    sudo install -Dm644 /dev/stdin /etc/vr-profiles.d/xreal-air-gen1.conf << 'EOF'
# Xreal Air Gen 1 — SBS glasses via DP-Alt over USB-C
VR_NAME="Xreal Air Gen 1"
VR_DETECT_TYPE="display"

# EDID matching
VR_EDID_NAME="Air"
VR_EDID_VENDOR="MRG"

# SBS trigger: glasses HPD fires when button pressed, EDID changes to 3840x1080
VR_SBS_WIDTH=3840
VR_SBS_HEIGHT=1080
VR_DESKTOP_WIDTH=1920
VR_DESKTOP_HEIGHT=1080

# USB HID init (W_DISP_MODE command, interface 4, 64-byte packet)
VR_DETECT_USB="3318:0424"
VR_HID_VENDOR="3318"
VR_HID_PRODUCT="0424"
VR_HID_INTERFACE=4
VR_HID_PAYLOAD_2D=fd:f5:d3:8e:e8:12:00:00:00:00:00:00:00:00:00:08:00:00:00:00:00:00:01:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
VR_HID_PAYLOAD_3D=fd:d9:b2:80:06:12:00:00:00:00:00:00:00:00:00:08:00:00:00:00:00:00:03:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00

VR_OPENXR_RUNTIME="monado"
VR_WIDTH=3840
VR_HEIGHT=1080
VR_REFRESH=60
VR_SCALE=1
VR_VIRTUAL_WIDTH=1920
VR_VIRTUAL_HEIGHT=1080
VR_DP_FORCE_RETRAIN=true
EOF
}

_write_profile_quest3_wivrn() {
    sudo install -Dm644 /dev/stdin /etc/vr-profiles.d/quest3-wivrn.conf << 'EOF'
VR_NAME="Meta Quest 3 (WiVRn)"
VR_DETECT_TYPE="service"
VR_DETECT_SERVICE="org.meumeu.wivrn"
VR_WIDTH=2064
VR_HEIGHT=2208
VR_REFRESH=72
VR_SCALE=1
VR_OPENXR_RUNTIME="wivrn"
EOF
}

_write_profile_samsung_odyssey() {
    sudo install -Dm644 /dev/stdin /etc/vr-profiles.d/samsung-odyssey-plus.conf << 'EOF'
VR_NAME="Samsung Odyssey+"
VR_DETECT_TYPE="display"
VR_EDID_NAME="ODYSSEY"
VR_DETECT_USB="045e:0659"
VR_CONNECTOR_HINT="HDMI-A-1"
VR_WIDTH=2880
VR_HEIGHT=1600
VR_REFRESH=90
VR_SCALE=1
VR_OPENXR_RUNTIME="monado"
EOF
}

###############################################################################
# Step 4: Patch and install Monado
###############################################################################
install_monado() {
    section "Installing patched Monado"

    local patch="$MONADO_PATCHES/0001-wayland-window-size.patch"
    [ -f "$patch" ] || die "Monado patch not found: $patch"

    # Find or fetch Monado AUR source
    local monado_src=""
    for candidate in \
        "$HOME/.cache/paru/clone/monado/monado-v"*/ \
        "$HOME/.cache/paru/clone/monado/src/monado-v"*/; do
        if [ -f "${candidate}src/xrt/compositor/main/comp_settings.c" ]; then
            monado_src="${candidate}"
            break
        fi
    done

    if [ -z "$monado_src" ]; then
        log "Fetching Monado AUR source via paru..."
        paru -G monado
        # Re-scan after fetch
        for candidate in "$HOME/.cache/paru/clone/monado/"*/; do
            if [ -f "${candidate}src/xrt/compositor/main/comp_settings.c" ]; then
                monado_src="${candidate}"
                break
            fi
        done
    fi

    [ -n "$monado_src" ] || die "Could not find Monado source. Run: paru -G monado"
    log "Monado source: $monado_src"

    local comp_settings="$monado_src/src/xrt/compositor/main/comp_settings.c"

    # Apply patch (idempotent — check for the replacement comment as sentinel)
    # The patch replaces /2 divisors in force_wayland block with an Xreal Air comment.
    if grep -q "Xreal Air SBS" "$comp_settings" 2>/dev/null; then
        log "Monado patch already applied, skipping"
    else
        log "Applying Monado window-size patch..."
        cd "$monado_src"
        git apply "$patch" 2>/dev/null || patch -p1 < "$patch"
    fi

    # Build
    log "Building Monado..."
    cmake -B "$monado_src/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DXRT_FEATURE_WINDOW_PEEK=OFF \
        "$monado_src"
    ninja -C "$monado_src/build" -j"$(nproc)"

    log "Installing Monado (sudo)..."
    sudo ninja -C "$monado_src/build" install

    log "Monado installed: $(monado-service --version 2>/dev/null || echo 'version check N/A')"
}

###############################################################################
# Step 5: Write wrapper scripts into BUILD_DIR
###############################################################################
write_scripts() {
    section "Writing wrapper scripts"

    _write_service_wrapper
    _write_startplasma_vr
    _write_kwinvr_settings
    _write_kwinvr_watcher

    chmod +x \
        "$BUILD_DIR/kwin-vr-service-wrapper.sh" \
        "$BUILD_DIR/startplasma-vr.sh" \
        "$BUILD_DIR/kwinvr-settings.sh" \
        "$BUILD_DIR/kwin-vr-watcher.sh"

    log "Wrapper scripts written to $BUILD_DIR"
}

_write_service_wrapper() {
    cat > "$BUILD_DIR/kwin-vr-service-wrapper.sh" << EOF
#!/bin/bash
# kwin-vr-service-wrapper.sh — KWin environment wrapper
# Launched by plasma-kwin_wayland.service via systemd override.
# Sets paths so KWin loads the VR-patched Qt and vr.so plugin.
# Only this process and its children get the custom environment.

# Custom kwin_wayland first on PATH (symlink → VR build)
export PATH="$BUILD_DIR:$XWAYLAND_INSTALL/bin:\$PATH"

# Plugin and QML paths — VR build first, then system fallback
export QT_PLUGIN_PATH="$KWIN_INSTALL/usr/lib/plugins:$QT_INSTALL/plugins:/usr/lib/qt6/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="$KWIN_INSTALL/usr/lib/qml:$QT_INSTALL/qml:/usr/lib/qt6/qml\${QML2_IMPORT_PATH:+:\$QML2_IMPORT_PATH}"
export QML_IMPORT_PATH="$KWIN_INSTALL/usr/lib/qml:$QT_INSTALL/qml:/usr/lib/qt6/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"

export XR_RUNTIME_JSON=/etc/xdg/openxr/1/active_runtime.json

# Qt 6.10.x crashes in QKdeTheme with NULL pointer in QStyleHintsPrivate.
# Safe for KWin — it manages theming via KDE config directly.
export QT_QPA_PLATFORMTHEME=generic

# Prevent KWin from picking up stale WAYLAND_DISPLAY/DISPLAY from previous XWayland
unset WAYLAND_DISPLAY DISPLAY

exec /usr/bin/kwin_wayland_wrapper "\$@"
EOF
}

_write_startplasma_vr() {
    cat > "$BUILD_DIR/startplasma-vr.sh" << EOF
#!/bin/bash
# startplasma-vr.sh — Plasma VR session launcher
# Called by SDDM when user selects "Plasma VR (Wayland)".
#
# IMPORTANT: Do NOT set LD_LIBRARY_PATH or QT_PLUGIN_PATH globally here.
# That poisons every Plasma service (kded6, polkit, etc.) with our custom Qt,
# causing ABI mismatches and crash loops. Only KWin gets the custom env via
# its systemd override (installed below).

OVERRIDE_DIR="\$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"

# ── SBS safety check ─────────────────────────────────────────────────────────
# If the glasses are already in SBS mode (3840x1080) at login, KWin's DRM
# backend will attempt a full modeset on startup — which hangs on Intel HD 520.
# Force them back to 2D via HID command before starting the session.
reset_sbs_if_active() {
    for conn_dir in /sys/class/drm/card*-DP-* /sys/class/drm/card*-HDMI-*; do
        [ -d "\$conn_dir" ] || continue
        mode_file="\$conn_dir/modes"
        [ -f "\$mode_file" ] || continue
        first_mode=\$(head -1 "\$mode_file" 2>/dev/null)
        if [ "\$first_mode" = "3840x1080" ]; then
            echo "[VR pre-flight] SBS mode active on \$(basename \$conn_dir), resetting to 2D..."
            python3 "$BUILD_DIR/xreal-sbs.py" 2d 2>/dev/null || true
            sleep 1
        fi
    done
}
reset_sbs_if_active

# ── Stop xr-driver ────────────────────────────────────────────────────────────
# xr-driver claims Xreal Air HID interfaces via libusb, blocking hidraw nodes.
systemctl --user stop xr-driver 2>/dev/null || true
systemctl --user mask xr-driver 2>/dev/null || true

# ── Rebind HID interfaces to usbhid ──────────────────────────────────────────
for dev in /sys/bus/usb/devices/*; do
    [ -f "\$dev/idVendor" ] || continue
    [ "\$(cat \$dev/idVendor 2>/dev/null)" = "3318" ] || continue
    busdev=\$(basename "\$dev")
    for iface in /sys/bus/usb/devices/\${busdev}:1.*/; do
        [ "\$(cat \$iface/bInterfaceClass 2>/dev/null)" = "03" ] || continue
        driver=\$(basename "\$(readlink \$iface/driver 2>/dev/null)" 2>/dev/null || echo "")
        if [ "\$driver" != "usbhid" ]; then
            ifname=\$(basename "\$iface")
            [ -n "\$driver" ] && echo "\$ifname" | sudo tee "/sys/bus/usb/drivers/\$driver/unbind" >/dev/null 2>&1 || true
            echo "\$ifname" | sudo tee /sys/bus/usb/drivers/usbhid/bind >/dev/null 2>&1 || true
        fi
    done
done

# ── Enable Monado socket activation ──────────────────────────────────────────
# VR plugin calls xrCreateInstance() → connects to monado_comp_ipc socket
# → triggers monado.socket → monado.service. Monado starts AFTER KWin is up.
systemctl --user enable monado.socket 2>/dev/null || true
systemctl --user start monado.socket 2>/dev/null || true

# ── Install KWin systemd override ────────────────────────────────────────────
mkdir -p "\$OVERRIDE_DIR"
cat > "\$OVERRIDE_DIR/vr-override.conf" << 'OVERRIDE'
[Service]
ExecStart=
ExecStart=$BUILD_DIR/kwin-vr-service-wrapper.sh --xwayland
OVERRIDE
systemctl --user daemon-reload

# ── Enable VR plugin ──────────────────────────────────────────────────────────
kwriteconfig6 --file kwinrc --group Plugins --key vrEnabled true 2>/dev/null || true

# ── Start session (blocks until logout) ──────────────────────────────────────
startplasma-wayland

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "\$OVERRIDE_DIR/vr-override.conf"
rmdir "\$OVERRIDE_DIR" 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user unmask xr-driver 2>/dev/null || true
EOF
}

_write_kwinvr_settings() {
    cat > "$BUILD_DIR/kwinvr-settings.sh" << EOF
#!/bin/bash
# kwinvr-settings.sh — Launch VR KCM with correct Qt environment
# The KCM links against our Qt 6.10.x which can't load inside system
# systemsettings6 (different Qt minor version, private API mismatch).

export PATH="$QT_INSTALL/bin:\$PATH"
export LD_LIBRARY_PATH="$KWIN_INSTALL/usr/lib:$QT_INSTALL/lib:$KDE_INSTALL/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$KWIN_INSTALL/usr/lib/plugins:$QT_INSTALL/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="$KWIN_INSTALL/usr/lib/qml:$QT_INSTALL/qml:/usr/lib/qt6/qml\${QML2_IMPORT_PATH:+:\$QML2_IMPORT_PATH}"
export QML_IMPORT_PATH="$KWIN_INSTALL/usr/lib/qml:$QT_INSTALL/qml:/usr/lib/qt6/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"

exec kcmshell6 kwinvr_kcm "\$@"
EOF
}

_write_kwinvr_watcher() {
    cat > "$BUILD_DIR/kwin-vr-watcher.sh" << EOF
#!/bin/bash
# kwin-vr-watcher.sh — Watch VR plugin source, auto-rebuild on change
set -e

SRC_DIR="$REPO_DIR/src/plugins/vr"
BUILD="$REPO_DIR/build"
DEBOUNCE=2

log() { echo "[\$(date '+%H:%M:%S')] \$1"; }

[ -d "\$SRC_DIR" ] || { log "ERROR: Source not found: \$SRC_DIR"; exit 1; }
[ -d "\$BUILD" ]   || { log "ERROR: Build dir not found: \$BUILD"; exit 1; }

rebuild() {
    log "Building vr + kwinvr_kcm..."
    cmake --build "\$BUILD" --target vr --target kwinvr_kcm -j\$(nproc) 2>&1 \
        && log "Build succeeded" || log "Build FAILED"
}

rebuild

inotifywait -m -r -e modify,create,delete,move \
    --include '\.(qml|cpp|h|kcfg|kcfgc|txt|xml)$' "\$SRC_DIR" |
while true; do
    read -t 86400 line || continue
    log "Change: \$line"
    while read -t "\$DEBOUNCE" line; do :; done
    rebuild
done
EOF
}

###############################################################################
# Step 6: Set up user systemd services
###############################################################################
setup_user_services() {
    section "Setting up user systemd services"

    local user_systemd="$HOME/.config/systemd/user"
    mkdir -p "$user_systemd/monado.service.d"

    # ── custodian service (user-level enable) ─────────────────────────────────
    # Unit file lives in /usr/lib/systemd/user/ (installed in step 3)
    systemctl --user enable kwin-vr-custodian.service 2>/dev/null || true

    # ── watcher service ───────────────────────────────────────────────────────
    cat > "$user_systemd/kwin-vr-watcher.service" << EOF
[Unit]
Description=KWin VR source watcher — auto-rebuild on change
After=default.target

[Service]
Type=simple
ExecStart=$BUILD_DIR/kwin-vr-watcher.sh
Restart=on-failure
RestartSec=5
Environment=PATH=$QT_INSTALL/bin:/usr/bin:/bin
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
    systemctl --user enable kwin-vr-watcher.service 2>/dev/null || true

    # ── monado service override ───────────────────────────────────────────────
    # Tune Monado for this hardware. Overrides the system-level monado.service.
    cat > "$user_systemd/monado.service.d/override.conf" << 'EOF'
[Service]
# Wayland compositing mode — glasses are a desktop output.
# KWin renders the VR scene; Monado presents via a Wayland window.
Environment="XRT_COMPOSITOR_FORCE_WAYLAND=1"
Environment="WAYLAND_DISPLAY=wayland-0"
Environment="XRT_COMPOSITOR_DEFAULT_FRAMERATE=60"
Environment="XRT_COMPOSITOR_FORCE_GPU_INDEX=0"
# 100% = native resolution. Default 140% (2688x1512/eye) exceeds Intel HD 520 bandwidth.
Environment="XRT_COMPOSITOR_SCALE_PERCENTAGE=100"
Restart=no
EOF

    # ── monado socket (enabled but not started — socket-activates on demand) ──
    systemctl --user enable monado.socket 2>/dev/null || true

    # ── mask xr-driver for this user ─────────────────────────────────────────
    ln -sf /dev/null "$user_systemd/xr-driver.service" 2>/dev/null || true

    systemctl --user daemon-reload
    log "User services configured"
}

###############################################################################
# Step 7: Ensure kwinvr config has safe defaults
###############################################################################
setup_kwinvr_config() {
    section "Setting kwinvr config defaults"

    local cfg="$HOME/.config/kwinvr"
    mkdir -p "$(dirname "$cfg")"

    # Only write if missing — don't overwrite user settings
    if [ ! -f "$cfg" ]; then
        cat > "$cfg" << 'EOF'
[General]
autoStart=false
blockOtherPointerMotion=false
defaultCurvature=0.1
followWorldUpAlignment=true
height=1080
refreshrate=60
scale=1
vignetteEnabled=false
width=1920
EOF
        log "Created $cfg with defaults"
    else
        # Ensure autoStart=false — must be false or VR tries to start at login
        # and crashes the display before KWin is ready.
        kwriteconfig6 --file kwinvr --group General --key autoStart false
        log "Ensured autoStart=false in existing $cfg"
    fi
}

###############################################################################
# Step 8: Verification
###############################################################################
verify() {
    section "Verification"
    local ok=true

    _check() {
        local label="$1" cond="$2"
        if eval "$cond" &>/dev/null; then
            log "PASS  $label"
        else
            err "FAIL  $label"
            ok=false
        fi
    }

    _check "kwin_wayland binary"       "[ -f '$KWIN_INSTALL/usr/bin/kwin_wayland' ]"
    _check "kwin_wayland symlink"      "[ -L '$BUILD_DIR/kwin_wayland' ]"
    _check "vr.so plugin"              "find '$KWIN_INSTALL' -name vr.so | grep -q ."
    _check "Qt Quick3D XR library"     "[ -f '$QT_INSTALL/lib/libQt6Quick3DXr.so' ]"
    _check "kwin-vr-custodian binary"  "[ -x /usr/lib/kwin-vr-custodian ]"
    _check "custodian service file"    "[ -f /usr/lib/systemd/user/kwin-vr-custodian.service ]"
    _check "monado.socket unit"        "[ -f /usr/lib/systemd/user/monado.socket ]"
    _check "plasma-vr.desktop"         "[ -f /usr/share/wayland-sessions/plasma-vr.desktop ]"
    _check "vr-profiles.d xreal"       "[ -f /etc/vr-profiles.d/xreal-air-gen1.conf ]"
    _check "udev rules"                "[ -f /usr/lib/udev/rules.d/70-kwin-vr.rules ]"
    _check "monado-service binary"     "command -v monado-service"
    _check "service wrapper script"    "[ -x '$BUILD_DIR/kwin-vr-service-wrapper.sh' ]"
    _check "startplasma-vr.sh"         "[ -x '$BUILD_DIR/startplasma-vr.sh' ]"
    _check "xwayland binary"           "[ -x '$XWAYLAND_INSTALL/bin/Xwayland' ]"
    _check "kwinvr config safe"        "grep -q 'autoStart=false' '$HOME/.config/kwinvr'"

    local rpath
    rpath=$(patchelf --print-rpath "$KWIN_INSTALL/usr/bin/kwin_wayland" 2>/dev/null)
    if echo "$rpath" | grep -q "$KWIN_INSTALL"; then
        log "PASS  kwin_wayland RPATH contains build dir"
    else
        err "FAIL  kwin_wayland RPATH looks wrong: $rpath"
        ok=false
    fi

    echo ""
    if $ok; then
        log "ALL CHECKS PASSED"
        echo ""
        log "Log out and select 'Plasma VR (Wayland)' at the SDDM login screen."
        log "The VR plugin activates via Ctrl+Meta+J once in session."
    else
        err "Some checks FAILED — review output above"
        exit 1
    fi
}

###############################################################################
# Main
###############################################################################
main() {
    section "KWin VR Installer"
    log "BUILD_DIR: $BUILD_DIR"
    log "USER:      $USER"

    preflight
    fix_rpath
    setup_symlink
    install_system_files
    install_monado
    write_scripts
    setup_user_services
    setup_kwinvr_config
    verify

    section "INSTALL COMPLETE"
    log "Total time: $SECONDS seconds"
}

main "$@" 2>&1 | tee "$BUILD_DIR/install.log"
