#!/usr/bin/env bash
# Flat-mode boot smoke test (M2): boots a real kwin_wayland --virtual with
# displayMode=Flat, activates VR over DBus, and asserts:
#   1. org.kde.kwinvr appears on the session bus
#   2. vrActive flips to true (no Monado / OpenXR loader involved)
#   3. the QML scene loads with zero type/load errors
#   4. the compositor is still alive afterwards
# This pins the bug class where renderer-seam QML only fails at runtime load
# (e.g. "Unable to assign QQuick3DPerspectiveCamera to QQuick3DXrCamera").
#
# Usage: flatboot-smoke.sh <build-bin-dir>
set -u

# Re-exec under a private dbus session with ALL output going to a file:
# dbus-activated daemons (xdg-desktop-portal etc.) inherit our stdout and
# outlive us — if that's ctest's pipe, ctest waits for EOF until timeout.
if [ -z "${FLATBOOT_INNER:-}" ]; then
    OUT=$(mktemp)
    FLATBOOT_INNER=1 dbus-run-session -- "$0" "$@" > "$OUT" 2>&1 < /dev/null
    rc=$?
    cat "$OUT"
    rm -f "$OUT"
    exit $rc
fi

BIN_DIR="${1:?usage: flatboot-smoke.sh <build-bin-dir>}"
KWIN="$BIN_DIR/kwin_wayland"
[ -x "$KWIN" ] || { echo "FAIL: $KWIN not executable"; exit 1; }

export HOME=$(mktemp -d) XDG_RUNTIME_DIR=$(mktemp -d)
chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p "$HOME/.config"
printf '[General]\ndisplayMode=Flat\n' > "$HOME/.config/kwinvr"

export QT_PLUGIN_PATH="$BIN_DIR"
export QT_LOGGING_RULES="kwinvr.debug=true"
export QT_FORCE_STDERR_LOGGING=1
# kwin_wayland must use its own QPA, not the offscreen one the test env exports
unset QT_QPA_PLATFORM

LOG="$HOME/kwin.log"
setsid "$KWIN" --virtual --no-lockscreen --no-global-shortcuts > "$LOG" 2>&1 &
KPID=$!
cleanup() {
    kill -TERM -"$KPID" 2>/dev/null
    sleep 1
    kill -KILL -"$KPID" 2>/dev/null
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1"
    echo "--- kwin.log tail:"
    tail -40 "$LOG"
    exit 1
}

# 1. kwinvr service appears on the bus
on_bus=0
for _ in $(seq 1 30); do
    if dbus-send --session --dest=org.freedesktop.DBus --print-reply / \
        org.freedesktop.DBus.ListNames 2>/dev/null | grep -q org.kde.kwinvr; then
        on_bus=1; break
    fi
    sleep 1
done
[ "$on_bus" = 1 ] || fail "org.kde.kwinvr never appeared on the session bus"

# 2. activate and poll vrActive until true
dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
    org.freedesktop.DBus.Properties.Set \
    string:org.kde.kwinvr string:vrActive variant:boolean:true \
    > /dev/null 2>&1 || fail "vrActive Set call failed"

active=0
for _ in $(seq 1 30); do
    if dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
        org.freedesktop.DBus.Properties.Get \
        string:org.kde.kwinvr string:vrActive 2>/dev/null \
        | grep -q 'boolean true'; then
        active=1; break
    fi
    sleep 1
done
[ "$active" = 1 ] || fail "vrActive never flipped to true"

# Let the QML engine finish loading before scanning for errors
sleep 5

# 3. zero QML load/type errors
QML_ERR_RE='Unable to assign|Cannot assign|is not a type|Failed to load QML|Type error|ReferenceError|TypeError'
if grep -qE "$QML_ERR_RE" "$LOG"; then
    echo "--- offending lines:"
    grep -E "$QML_ERR_RE" "$LOG"
    fail "QML errors found in flat-mode boot"
fi

# 4. compositor survived
kill -0 "$KPID" 2>/dev/null || fail "kwin_wayland died during activation"

echo "PASS: flat-mode boot clean (kwinvr on bus, vrActive=true, 0 QML errors)"
exit 0
