#!/bin/bash
# Scan /sys/bus/usb for VID:PID matches against profiles in /etc/vr-profiles.d/
# Output: path to matching profile, or exit 1 if none found
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
