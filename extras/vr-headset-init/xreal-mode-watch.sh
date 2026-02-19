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

# Find the correct DRM card for this connector (not always card0 — hybrid GPU systems)
DRM_CARD=""
for card_conn in /sys/class/drm/card*-"${CONNECTOR}"; do
    [ -d "$card_conn" ] || continue
    DRM_CARD="$card_conn"
    break
done
if [ -z "$DRM_CARD" ]; then
    echo "[xreal-mode-watch] No DRM card found for connector ${CONNECTOR}, exiting"
    exit 1
fi

MODES_FILE="${DRM_CARD}/modes"
STATUS_FILE="${DRM_CARD}/status"
IPC_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/monado_comp_ipc"
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
    local timeout="${1:-30}"
    for i in $(seq 1 "$timeout"); do
        if dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Get \
            string:org.kde.kwinvr string:vrActive &>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Wait for Monado IPC socket to appear (service fully initialised)
wait_for_monado() {
    local timeout="${1:-15}"
    log "Waiting for Monado IPC socket..."
    for i in $(seq 1 "$timeout"); do
        if [ -S "$IPC_SOCKET" ]; then
            log "Monado ready after ${i}s"
            return 0
        fi
        sleep 1
    done
    log "Monado IPC socket did not appear within ${timeout}s"
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

# Stop Monado fast via direct PID kill (systemctl stop can block 10-20s on cleanup)
stop_monado() {
    local pid
    pid=$(systemctl --user show -p MainPID --value monado.service 2>/dev/null)
    if [ -n "$pid" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null; then
        log "Stopping Monado (PID $pid)..."
        kill -TERM "$pid" 2>/dev/null
        # Wait up to 2s for graceful shutdown
        local i
        for i in $(seq 1 20); do
            kill -0 "$pid" 2>/dev/null || { log "Monado stopped gracefully"; break; }
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            log "Monado didn't stop in 2s, sending SIGKILL"
            kill -9 "$pid" 2>/dev/null
            sleep 0.5
        fi
        systemctl --user reset-failed monado.service 2>/dev/null
    elif systemctl --user is-active --quiet monado.service 2>/dev/null; then
        # Fallback: systemd says active but no PID (transitioning state)
        log "Stopping Monado via systemd..."
        timeout 3 systemctl --user stop monado.service 2>/dev/null || {
            systemctl --user kill -s SIGKILL monado.service 2>/dev/null
            sleep 0.5
        }
        systemctl --user reset-failed monado.service 2>/dev/null
    fi
    # Remove stale IPC socket so wait_for_monado waits for the NEW instance
    rm -f "$IPC_SOCKET"
    log "Monado stopped"
}

# Check if connector is still in SBS mode
check_sbs_active() {
    local s m
    s=$(cat "$STATUS_FILE" 2>/dev/null)
    [ "$s" = "connected" ] || return 1
    m=$(get_first_mode)
    [ "$m" = "$SBS_MODE" ] || return 1
    return 0
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

    # Deactivate VR via D-Bus first (lets KWin tear down XR session cleanly)
    dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
        org.freedesktop.DBus.Properties.Set \
        string:org.kde.kwinvr string:vrActive variant:boolean:false 2>/dev/null
    sleep 1
    log "VR deactivated"

    stop_monado

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

    # 1. Kill old Monado FIRST (fast, before the slow apply_mode)
    stop_monado

    # 2. Apply SBS mode (triggers modeset + DP link retrain at higher bandwidth)
    apply_mode 3840 1080 60

    # Re-check: glasses may have cycled during apply_mode (~5s)
    if ! check_sbs_active; then
        log "Lost SBS mode during apply_mode, aborting activation"
        LAST_MODE=$(get_first_mode)
        return
    fi

    # 3. Update kwinvr config for Xreal Air (merge, don't overwrite user settings)
    kwriteconfig6 --file kwinvr --group General --key autoStart true
    kwriteconfig6 --file kwinvr --group General --key width "${VR_WIDTH}"
    kwriteconfig6 --file kwinvr --group General --key height "${VR_HEIGHT}"
    kwriteconfig6 --file kwinvr --group General --key scale "${VR_SCALE}"
    kwriteconfig6 --file kwinvr --group General --key refreshrate "${VR_REFRESH}"

    # 4. Start Monado and wait for IPC socket
    systemctl --user start monado.service
    if ! wait_for_monado 15; then
        log "Monado failed to start, aborting VR activation"
        return
    fi
    # Give Monado time to fully initialize after socket creation
    sleep 2

    # Re-check: glasses may have cycled during Monado startup
    if ! check_sbs_active; then
        log "Lost SBS mode during Monado start, aborting activation"
        stop_monado
        LAST_MODE=$(get_first_mode)
        return
    fi

    # 5. Activate VR via D-Bus (with retry — KWin may fail on first attempt)
    if ! wait_for_kwin_vr 10; then
        log "KWin VR D-Bus not available"
        VR_ACTIVE=true
        LAST_MODE="$SBS_MODE"
        return
    fi

    local attempt
    for attempt in 1 2 3; do
        dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Set \
            string:org.kde.kwinvr string:vrActive variant:boolean:true 2>/dev/null
        sleep 2
        # Verify it stuck
        local vr_state
        vr_state=$(dbus-send --session --dest=org.kde.KWin --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Get \
            string:org.kde.kwinvr string:vrActive 2>/dev/null | grep -o "true\|false")
        if [ "$vr_state" = "true" ]; then
            log "VR activated (attempt $attempt)"
            break
        fi
        log "VR activation attempt $attempt failed (vrActive=$vr_state), retrying..."
        sleep 2
    done

    VR_ACTIVE=true
    LAST_MODE="$SBS_MODE"
}

# Wait for connector to be available
log "Watching ${VR_NAME} on ${CONNECTOR} (card: ${DRM_CARD})"
while [ ! -f "$STATUS_FILE" ]; do sleep 1; done

# Wait for KWin to be up
log "Waiting for KWin VR interface..."
wait_for_kwin_vr 30 || log "Warning: KWin VR not found, continuing anyway"

log "Current mode: $(get_first_mode)"

# Force 60Hz on startup (Xreal Air Gen 1 EDID advertises 120Hz but can't
# sustain it over USB-C DP-alt on some platforms)
apply_mode 1920 1080 60

# Set LAST_MODE to desktop so the main loop detects if EDID shows SBS
LAST_MODE="$DESKTOP_MODE"

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
                    # Apply 60Hz (glasses may default to 120Hz after mode switch)
                    apply_mode 1920 1080 60
                    ;;
                *)
                    log "Unknown mode: $mode"
                    ;;
            esac
            # Set LAST_MODE to the mode we just processed, NOT a fresh DRM read.
            # A fresh read can race with HPD events during apply_mode (5s) —
            # the EDID may have already changed to the next mode, causing
            # the watcher to think it already handled it (stuck forever).
            LAST_MODE="$mode"
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
