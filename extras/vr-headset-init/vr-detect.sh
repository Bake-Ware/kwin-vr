#!/bin/bash
# Scan for VR headsets against profiles in /etc/vr-profiles.d/
# Detection chain: USB VID:PID → display connector → exit 1
# Output: path to matching profile, or exit 1 if none found

# ── Pass 1: USB VID:PID match ───────────────────────────────────────────────
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

# ── Pass 2: Display connector match (DP-alt-mode headsets) ───────────────────
for profile in /etc/vr-profiles.d/*.conf; do
    [ -f "$profile" ] || continue
    VR_DISPLAY_CONNECTOR=""
    source "$profile"
    [ -z "$VR_DISPLAY_CONNECTOR" ] && continue
    # Check all DRM cards for a connected output matching the profile
    for card_conn in /sys/class/drm/card*-"${VR_DISPLAY_CONNECTOR}"/status; do
        [ -f "$card_conn" ] || continue
        if [ "$(cat "$card_conn" 2>/dev/null)" = "connected" ]; then
            echo "$profile"
            exit 0
        fi
    done
done

exit 1
