#!/bin/bash
# Detect VR hardware and run headset-specific init
# Retry up to 20 times (10 seconds) to handle USB enumeration race

PROFILE=""
for i in $(seq 1 20); do
    PROFILE=$(/usr/lib/vr-headset-init/vr-detect.sh 2>/dev/null)
    [ $? -eq 0 ] && break
    PROFILE=""
    sleep 0.5
done

# WiVRn fallback: if USB scan found nothing, check if WiVRn is the active
# OpenXR runtime and find a manual-detect WiVRn profile (e.g. Quest 3).
# USB-detected headsets always take priority over manual/network profiles.
if [ -z "$PROFILE" ]; then
    ACTIVE_RUNTIME="/etc/xdg/openxr/1/active_runtime.json"
    if [ -f "$ACTIVE_RUNTIME" ] && grep -q "wivrn" "$ACTIVE_RUNTIME" 2>/dev/null; then
        for conf in /etc/vr-profiles.d/*.conf; do
            [ -f "$conf" ] || continue
            unset VR_DETECT_MANUAL VR_OPENXR_RUNTIME
            . "$conf"
            if [ "${VR_DETECT_MANUAL:-}" = "true" ] && [ "${VR_OPENXR_RUNTIME:-}" = "wivrn" ]; then
                PROFILE="$conf"
                break
            fi
        done
    fi
fi

if [ -z "$PROFILE" ]; then
    echo "No VR headset detected after 10s"
    echo "none" > /run/vr-detected
    exit 0
fi

source "$PROFILE"
echo "$PROFILE" > /run/vr-detected
chmod 644 /run/vr-detected

echo "Detected: $VR_NAME"

# Run headset-specific init if defined
if [ -n "$VR_BOOT_INIT" ] && [ -x "$VR_BOOT_INIT" ]; then
    echo "Running init: $VR_BOOT_INIT"
    "$VR_BOOT_INIT"
fi
