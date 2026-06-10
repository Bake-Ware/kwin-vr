#!/usr/bin/env bash
# Flat-mode boot smoke test (M2): boots a real kwin_wayland --virtual with
# displayMode=Flat, activates VR over DBus, and asserts:
#   1. org.kde.kwinvr appears on the session bus
#   2. vrActive flips to true (no Monado / OpenXR loader involved)
#   3. the QML scene loads with zero type/load errors
#   4. a captured frame actually rendered (non-black — the black-screen
#      regression class this fork was born fighting)
#   5. the compositor is still alive afterwards
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

# 4. captured frame actually rendered (retry: renderer may still be warming up)
FRAME="$HOME/frame.ppm"
grabbed=0
for _ in $(seq 1 10); do
    if dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
        org.kde.kwinvr.captureWorkspaceFrame "string:$FRAME" 2>/dev/null \
        | grep -q 'boolean true' && [ -s "$FRAME" ]; then
        grabbed=1; break
    fi
    sleep 1
done

if [ "$grabbed" != 1 ]; then
    # Quick3D needs an RHI-backed scene graph; the CI container has no
    # /dev/dri and kwin falls back to software compositing, so View3D
    # renders nothing there by design. Skip ONLY on that exact marker —
    # anywhere GL exists this stays a hard assertion. Issue: GL-in-container.
    if grep -q 'Qt Quick 3D is not functional' "$LOG"; then
        echo "SKIP: no RHI scene graph in this environment — render assertion skipped (boot asserts still apply)"
    else
        fail "captureWorkspaceFrame never produced a frame"
    fi
else
python3 - "$FRAME" <<'EOF' || fail "frame analysis: rendered frame is black/empty"
import sys
data = open(sys.argv[1], 'rb').read()
# Qt writes plain P6: "P6\nW H\n255\n" + RGB bytes (no comments)
magic, dims, maxval, pixels = data.split(b'\n', 3)
assert magic == b'P6', f"not a P6 ppm: {magic}"
w, h = map(int, dims.split())
# Internal-QPA windows stay 1x1 without explicit geometry (MainFlat sets
# width/height from Screen) — pin that here.
assert w >= 320 and h >= 240, f"window never got real geometry: {w}x{h}"
n = w * h
# mean over a sparse sample; stride must not be a multiple of 3 or we'd
# sample a single channel. Skyblue clear color ~190 mean, black 0.
step = max(1, n // 10000) * 3 + 1
sample = pixels[:n * 3:step]
mean = sum(sample) / len(sample)
print(f"frame {w}x{h}, sampled mean channel value {mean:.1f}")
assert mean > 15, f"frame is essentially black (mean {mean:.1f})"
EOF
fi

# 5. compositor survived
kill -0 "$KPID" 2>/dev/null || fail "kwin_wayland died during activation"

echo "PASS: flat-mode boot clean (kwinvr on bus, vrActive=true, 0 QML errors, frame rendered)"
exit 0
