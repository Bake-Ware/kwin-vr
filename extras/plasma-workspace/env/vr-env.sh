#!/bin/bash
# VR Auto-Boot Environment Setup
# Runs before KWin starts — reads /run/vr-detected written by vr-headset-init.service

DETECTED=$(cat /run/vr-detected 2>/dev/null)
if [ -z "$DETECTED" ] || [ "$DETECTED" = "none" ]; then
    # No headset — vanilla desktop
    unset KWIN_FORCE_DESKTOP_OUTPUTS
    exit 0
fi

source "$DETECTED"

# Fix Qt GLES 3.x font rendering (GL_ALPHA → GL_R8 with swizzle) — ARM only
if [ "$(uname -m)" = "aarch64" ] && [ -f /usr/lib/libgl_alpha_fix.so ]; then
    export LD_PRELOAD="/usr/lib/libgl_alpha_fix.so${LD_PRELOAD:+:$LD_PRELOAD}"
fi

# NVIDIA env vars — only set if the headset display is on the NVIDIA GPU.
# On hybrid GPU laptops (NVIDIA + AMD iGPU), the headset may be on the iGPU,
# and forcing NVIDIA rendering would break modesetting on that connector.
if lsmod 2>/dev/null | grep -q "^nvidia " && [ -n "$VR_DISPLAY_CONNECTOR" ]; then
    VR_GPU_DRIVER=""
    for card_conn in /sys/class/drm/card*-"${VR_DISPLAY_CONNECTOR}"/status; do
        [ -f "$card_conn" ] || continue
        card_dir=$(dirname "$card_conn")
        card_base=$(echo "$card_dir" | sed 's|-.*||')  # /sys/class/drm/card2
        VR_GPU_DRIVER=$(basename "$(readlink "$card_base/device/driver")" 2>/dev/null)
        break
    done
    if [ "$VR_GPU_DRIVER" = "nvidia" ]; then
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export GBM_BACKEND=nvidia-drm
        export WLR_NO_HARDWARE_CURSORS=1
    fi
    unset VR_GPU_DRIVER
elif lsmod 2>/dev/null | grep -q "^nvidia " && [ -z "$VR_DISPLAY_CONNECTOR" ]; then
    # Network headset (no display connector) — NVIDIA is the only render GPU
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export WLR_NO_HARDWARE_CURSORS=1
fi

# Set KWin env for headset display
if [ -n "$VR_DISPLAY_CONNECTOR" ]; then
    export KWIN_FORCE_DESKTOP_OUTPUTS="$VR_DISPLAY_CONNECTOR"
fi

# For LOCAL headsets (Samsung, Xreal), pin KWin to Monado so WiVRn's
# active_runtime symlink management can't hijack the session.
# For network headsets (Quest via WiVRn), vr-env.sh exits early (no USB detect),
# so XR_RUNTIME_JSON stays unset — letting the dynamic symlink work.
if [ "$VR_OPENXR_RUNTIME" != "wivrn" ]; then
    export XR_RUNTIME_JSON="/usr/share/openxr/1/openxr_monado.json"
fi

# Update kwinvr config keys — preserves user settings like headgaze, curvature, etc.
AUTO_START="${VR_AUTO_START:-true}"
KWINVR_CFG="$HOME/.config/kwinvr"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key xrTestEnabled false
kwriteconfig6 --file "$KWINVR_CFG" --group General --key autoStart "$AUTO_START"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key width "$VR_WIDTH"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key height "$VR_HEIGHT"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key scale "$VR_SCALE"
kwriteconfig6 --file "$KWINVR_CFG" --group General --key refreshrate "$VR_REFRESH"

# ── Watch service management ─────────────────────────────────────────────────
# Stop ALL watch services first (clean slate), then start the one the profile needs.
# VR_WATCH_SERVICE is set in the profile (e.g. "wivrn-watch", "xreal-mode-watch", or "")
ALL_WATCH_SERVICES="xreal-mode-watch wivrn-watch"

for svc in $ALL_WATCH_SERVICES; do
    systemctl --user disable --now "${svc}.service" 2>/dev/null || true
done

if [ -n "${VR_WATCH_SERVICE:-}" ]; then
    systemctl --user enable --now "${VR_WATCH_SERVICE}.service" 2>/dev/null || true
fi
