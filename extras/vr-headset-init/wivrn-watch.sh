#!/bin/bash
# Watch WiVRn D-Bus HeadsetConnected property and toggle KWin VR mode
# When Quest connects → activate VR; when it disconnects → deactivate VR

set -euo pipefail

WIVRN_DEST="io.github.wivrn.Server"
WIVRN_PATH="/io/github/wivrn/Server"
WIVRN_IFACE="io.github.wivrn.Server"

KWINVR_DEST="org.kde.kwinvr"
KWINVR_PATH="/KwinVr"

get_headset_connected() {
    gdbus call --session \
        --dest "$WIVRN_DEST" \
        --object-path "$WIVRN_PATH" \
        --method org.freedesktop.DBus.Properties.Get \
        "$WIVRN_IFACE" HeadsetConnected 2>/dev/null | grep -q "true"
}

get_vr_active() {
    gdbus call --session \
        --dest "$KWINVR_DEST" \
        --object-path "$KWINVR_PATH" \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.kwinvr vrActive 2>/dev/null | grep -q "true"
}

set_vr_active() {
    local active="$1"
    dbus-send --session --dest="$KWINVR_DEST" \
        "$KWINVR_PATH" org.kde.kwinvr.setVrActive "boolean:$active" 2>/dev/null || true
}

echo "wivrn-watch: waiting for WiVRn D-Bus service..."

# Wait for WiVRn to appear on D-Bus
while ! gdbus call --session --dest "$WIVRN_DEST" --object-path "$WIVRN_PATH" \
    --method org.freedesktop.DBus.Properties.Get "$WIVRN_IFACE" HeadsetConnected &>/dev/null; do
    sleep 2
done
echo "wivrn-watch: WiVRn D-Bus service found"

# Track whether we activated VR (so we only deactivate what we started)
WE_ACTIVATED=false

# Check initial state
if get_headset_connected && ! get_vr_active; then
    echo "wivrn-watch: headset already connected, activating VR"
    set_vr_active true
    WE_ACTIVATED=true
fi

# Monitor PropertiesChanged signals (process substitution avoids subshell)
while IFS= read -r line; do
    if [[ "$line" == *"PropertiesChanged"*"HeadsetConnected"* ]]; then
        if [[ "$line" == *"<true>"* ]]; then
            if ! get_vr_active; then
                echo "wivrn-watch: headset connected, activating VR"
                set_vr_active true
                WE_ACTIVATED=true
            else
                echo "wivrn-watch: headset connected, VR already active"
            fi
        elif [[ "$line" == *"<false>"* ]]; then
            if [ "$WE_ACTIVATED" = true ]; then
                echo "wivrn-watch: headset disconnected, deactivating VR"
                set_vr_active false
                WE_ACTIVATED=false
            else
                echo "wivrn-watch: headset disconnected, VR not started by us"
            fi
        fi
    fi
done < <(gdbus monitor --session --dest "$WIVRN_DEST" --object-path "$WIVRN_PATH" 2>/dev/null)
