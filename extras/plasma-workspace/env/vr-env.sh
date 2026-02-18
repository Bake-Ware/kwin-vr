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

# Fix Qt GLES 3.x font rendering (GL_ALPHA → GL_R8 with swizzle)
export LD_PRELOAD="/usr/lib/libgl_alpha_fix.so${LD_PRELOAD:+:$LD_PRELOAD}"

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

# Start mode-watch for headsets that need it (e.g. Xreal Air SBS button)
if [ "$VR_AUTO_START" = "false" ]; then
    systemctl --user enable --now xreal-mode-watch.service 2>/dev/null || true
else
    systemctl --user disable --now xreal-mode-watch.service 2>/dev/null || true
fi
