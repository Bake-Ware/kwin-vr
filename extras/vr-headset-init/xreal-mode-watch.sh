#!/bin/bash
# Watch Xreal Air glasses for SBS mode switch (physical button press).
# When resolution changes from 1920x1080 to 3840x1080, activate VR.
# When it changes back, deactivate VR.
#
# How DP link retraining works:
# When the glasses switch modes, their EDID changes and an HPD event fires.
# KWin re-reads the EDID but may not commit a modeset automatically.
# We explicitly set the mode via kscreen-doctor, which triggers a full
# atomic commit -> bridge_disable -> bridge_enable -> dw_dp_link_train()
# at the correct bandwidth for the new resolution.

DETECTED=$(cat /run/vr-detected 2>/dev/null)
if [ -z "$DETECTED" ] || [ "$DETECTED" = "none" ]; then
    echo "[xreal-mode-watch] No VR headset detected, exiting"
    exit 0
fi
source "$DETECTED"

CONNECTOR="${VR_DISPLAY_CONNECTOR:-DP-1}"
MODES_FILE="/sys/class/drm/card0-${CONNECTOR}/modes"
STATUS_FILE="/sys/class/drm/card0-${CONNECTOR}/status"
SBS_MODE="3840x1080"
DESKTOP_MODE="1920x1080"
POLL_INTERVAL=2
LAST_MODE=""
VR_ACTIVE=false

log() { echo "[xreal-mode-watch] $*"; }

get_first_mode() {
    head -1 "$MODES_FILE" 2>/dev/null
}

wait_for_kwin_vr() {
    for i in $(seq 1 30); do
        if dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Get \
            string:org.kde.kwinvr string:vrActive &>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_connected() {
    local timeout="${1:-15}"
    log "Waiting for connector to come back..."
    for i in $(seq 1 "$timeout"); do
        local s
        s=$(cat "$STATUS_FILE" 2>/dev/null)
        if [ "$s" = "connected" ]; then
            log "Connector reconnected after ${i}s"
            return 0
        fi
        sleep 1
    done
    log "Connector did not reconnect within ${timeout}s"
    return 1
}

# Force a specific mode on the connector via kscreen-doctor.
# This triggers a full atomic modeset including DP link retraining.
apply_mode() {
    local width="$1"
    local height="$2"
    local refresh="${3:-60}"
    local target="${width}x${height}"

    log "Applying mode ${target}@${refresh}Hz on ${CONNECTOR}"

    # Wait for HPD event to settle and EDID to be fully re-read by KWin
    sleep 3

    # Set the mode - this triggers atomic commit -> bridge disable/enable -> link train
    local result
    result=$(WAYLAND_DISPLAY=wayland-0 kscreen-doctor "output.${CONNECTOR}.mode.${target}@${refresh}" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ] && [ -n "$result" ]; then
        log "kscreen-doctor mode set failed (rc=$rc): $result"
        log "Trying fallback: mode index 1"
        WAYLAND_DISPLAY=wayland-0 kscreen-doctor "output.${CONNECTOR}.mode.1" 2>/dev/null
    fi

    sleep 2
    log "Mode applied"
}

# Stop VR services only - no display mode changes
stop_vr() {
    log "Stopping VR services"

    # Deactivate VR via D-Bus
    dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
        org.freedesktop.DBus.Properties.Set \
        string:org.kde.kwinvr string:vrActive variant:boolean:false 2>/dev/null
    log "VR deactivated"

    # Stop Monado
    systemctl --user stop monado.service
    sleep 1
    log "Monado stopped"

    # Set autoStart=false (merge, don't overwrite user settings)
    kwriteconfig6 --file kwinvr --group General --key autoStart false
    kwriteconfig6 --file kwinvr --group General --key width "${VR_WIDTH}"
    kwriteconfig6 --file kwinvr --group General --key height "${VR_HEIGHT}"
    kwriteconfig6 --file kwinvr --group General --key scale "${VR_SCALE}"
    kwriteconfig6 --file kwinvr --group General --key refreshrate "${VR_REFRESH}"

    VR_ACTIVE=false
}

activate_vr() {
    log "SBS mode detected (${SBS_MODE}) - activating VR"

    # 1. Apply SBS mode (triggers modeset + DP link retrain at higher bandwidth)
    apply_mode 3840 1080 60

    # 2. Update kwinvr config for Xreal Air (merge, don't overwrite user settings)
    kwriteconfig6 --file kwinvr --group General --key autoStart true
    kwriteconfig6 --file kwinvr --group General --key width "${VR_WIDTH}"
    kwriteconfig6 --file kwinvr --group General --key height "${VR_HEIGHT}"
    kwriteconfig6 --file kwinvr --group General --key scale "${VR_SCALE}"
    kwriteconfig6 --file kwinvr --group General --key refreshrate "${VR_REFRESH}"

    # 3. Restart Monado to pick up SBS mode
    systemctl --user restart monado.service
    sleep 3

    # 4. Activate VR via D-Bus
    if wait_for_kwin_vr; then
        dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Set \
            string:org.kde.kwinvr string:vrActive variant:boolean:true
        log "VR activated"
    else
        log "KWin VR D-Bus not available"
    fi

    VR_ACTIVE=true
    LAST_MODE=$(get_first_mode)
}

# Wait for connector to be available
log "Watching ${VR_NAME} on ${CONNECTOR}..."
while [ ! -f "$STATUS_FILE" ]; do sleep 1; done

# Wait for KWin to be up
log "Waiting for KWin VR interface..."
wait_for_kwin_vr || log "Warning: KWin VR not found, continuing anyway"

LAST_MODE=$(get_first_mode)
log "Current mode: ${LAST_MODE:-none}"

# Force 60Hz on startup (Xreal Air Gen 1 EDID advertises 120Hz but can't handle it)
apply_mode 1920 1080 60

while true; do
    status=$(cat "$STATUS_FILE" 2>/dev/null)

    if [ "$status" = "connected" ]; then
        mode=$(get_first_mode)

        if [ "$mode" != "$LAST_MODE" ] && [ -n "$mode" ]; then
            log "Mode changed: ${LAST_MODE:-none} -> $mode"

            case "$mode" in
                "$SBS_MODE")
                    if ! $VR_ACTIVE; then
                        activate_vr
                    fi
                    ;;
                "$DESKTOP_MODE")
                    if $VR_ACTIVE; then
                        stop_vr
                    fi
                    # Apply 60Hz (glasses default to 120Hz which doesn't work)
                    apply_mode 1920 1080 60
                    ;;
                *)
                    log "Unknown mode: $mode"
                    ;;
            esac
            LAST_MODE=$(get_first_mode)
        fi
    elif [ "$status" = "disconnected" ]; then
        if $VR_ACTIVE; then
            log "Connector disconnected while VR active"
            stop_vr
        fi
        # Wait for reconnection, then let the main loop handle the new mode
        if wait_for_connected; then
            # Give KWin time to process the HPD reconnect and read EDID
            sleep 2
            LAST_MODE=""
        fi
    fi

    sleep "$POLL_INTERVAL"
done
