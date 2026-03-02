#!/bin/bash
# Xreal Air boot init: set permissions, initialize to 2D mode, trigger EDID re-read.
# The glasses may boot at 640x480 until a W_DISP_MODE 2D command is sent via HID.
# After the HID command, a DP HPD cycle causes KWin to re-read the 1920x1080 EDID.
# When the user presses the SBS button, mode changes to 3840x1080 and the
# mode-watcher auto-activates VR.
chmod 666 /dev/hidraw* 2>/dev/null

# Wait briefly for USB HID interfaces to fully enumerate
sleep 1

# Send 2D mode init command to glasses
python3 /usr/lib/vr-headset-init/xreal-sbs-switch.py --2d 2>&1 | logger -t xreal-init || true

# Trigger DP HPD so KWin re-reads the EDID (now advertising 1920x1080)
# Requires root; try sudo first, fall back silently if unavailable.
sleep 0.5
for card_conn in /sys/class/drm/card*-DP-1/status; do
    [ -f "$card_conn" ] || continue
    card_dir=$(dirname "$card_conn")
    sudo sh -c "echo detect > '$card_dir/status'" 2>/dev/null \
        || echo detect > "$card_dir/status" 2>/dev/null \
        || true
done
