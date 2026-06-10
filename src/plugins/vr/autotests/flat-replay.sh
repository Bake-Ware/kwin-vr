#!/usr/bin/env bash
# Input-replay harness v0 (M2): scripted interaction sequences against the
# flat workspace, asserting scene END-STATE — the anti-regression pattern from
# the roadmap. v0 drives the renderer-seam API (the same functions the input
# grammar calls); raw-input-event replay arrives with M5's action layer.
#
# Covers: VOC-FLAT-030 (look), VOC-WORLD-040 (world grab via grab(true)),
# VOC-WORLD-050 (reset view), VOC-GRAB-050 (scroll depth, world),
# VOC-PLACE-* (real Wayland client lands in the scene and is auto-placed).
#
# Usage: flat-replay.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flat-replay.sh <build-bin-dir>}"
boot_flat_kwin "$BIN_DIR"
activate_vr

# Scene present and idle
assert_eq "$(vreval '(!!flatScene.workspace).toString()')" "true" "workspace exists"
assert_eq "$(vreval 'flatScene.workspace.worldGrabbed.toString()')" "false" "world not grabbed at start"

# --- VOC-FLAT-030: look moves the head rig, pitch clamps at 89 ---
vreval 'flatScene.lookBy(-100, -200)' > /dev/null   # yaw += 100*s, pitch += 200*s (s=0.15)
yaw=$(vreval 'flatScene.lookYaw.toFixed(1)')
pitch=$(vreval 'flatScene.lookPitch.toFixed(1)')
assert_eq "$yaw" "15.0" "lookBy yaw (100px * 0.15)"
assert_eq "$pitch" "30.0" "lookBy pitch (200px * 0.15)"
vreval 'flatScene.lookBy(0, -10000)' > /dev/null
assert_eq "$(vreval 'flatScene.lookPitch.toFixed(1)')" "89.0" "pitch clamps at +89"
vreval 'flatScene.lookBy(100, 10000); undefined' > /dev/null
assert_eq "$(vreval 'flatScene.lookPitch.toFixed(1)')" "-89.0" "pitch clamps at -89"

# --- VOC-WORLD-040 + VOC-GRAB-050: world grab, scroll depth, release ---
vreval 'flatScene.workspace.grab(true)' > /dev/null
assert_eq "$(vreval 'flatScene.workspace.worldGrabbed.toString()')" "true" "grab(true) world-grabs"
z0=$(vreval 'flatScene.workspace.grabbed.position.z.toFixed(2)')
vreval 'flatScene.workspace.scrollGrab(5)' > /dev/null
z1=$(vreval 'flatScene.workspace.grabbed.position.z.toFixed(2)')
[ "$z0" != "$z1" ] || fail "scrollGrab(5) did not change grabbed depth (z stayed $z0)"
echo "ok: scrollGrab changed world depth $z0 -> $z1"
vreval 'flatScene.workspace.release()' > /dev/null
assert_eq "$(vreval 'flatScene.workspace.worldGrabbed.toString()')" "false" "release() ends world grab"

# --- VOC-WORLD-050: reset view runs without error ---
assert_eq "$(vreval 'flatScene.workspace.resetView(); "done"')" "done" "resetView() executes"

# --- VOC-PLACE: a real Wayland client lands in the scene ---
# Must be the Qt 6 runtime: a Qt 5 `qml` in PATH silently loads nothing
# ("Did not load any objects") on versionless imports.
QML_BIN=""
for _c in /usr/lib/qt6/bin/qml "$(command -v qml6 2>/dev/null)" "$(command -v qml 2>/dev/null)"; do
    [ -n "$_c" ] && [ -x "$_c" ] || continue
    case "$("$_c" --version 2>/dev/null)" in
        *" 6."*) QML_BIN=$_c; break ;;
    esac
done
if [ -n "$QML_BIN" ]; then
    base=$(vreval 'flatScene.workspace.appWindows.count')
    cat > "$HOME/client.qml" <<'EOF'
import QtQuick
Window { visible: true; width: 320; height: 240; title: "replay-client"; color: "orange" }
EOF
    env -u QT_PLUGIN_PATH -u QT_FORCE_STDERR_LOGGING \
        WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        setsid "$QML_BIN" "$HOME/client.qml" > "$HOME/client.log" 2>&1 &
    CPID=$!

    if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 1))" 15 > /dev/null; then
        echo "--- client.log:"; cat "$HOME/client.log"
        fail "client window never appeared in the workspace (count stuck at $(vreval 'flatScene.workspace.appWindows.count'), base $base)"
    fi
    echo "ok: client window entered the scene (count $base -> $((base + 1)))"

    # Auto-placement gave it real size and registered it
    w=$(vreval "flatScene.workspace.appWindows.objectAt($base).itemSize.width.toFixed(0)")
    [ "${w:-0}" != "0" ] || fail "client window has zero itemSize — not placed"
    echo "ok: client window placed with itemSize.width=$w"

    kill -TERM -"$CPID" 2>/dev/null
    if ! vreval_wait 'flatScene.workspace.appWindows.count' "$base" 15 > /dev/null; then
        fail "client window did not leave the scene after close"
    fi
    echo "ok: client window left the scene on close"
else
    echo "SKIP: Qt 6 qml runtime not found — client placement assertions skipped"
fi

echo "PASS: flat replay v0 — look/world-grab/depth/release/reset/placement end-states verified"
exit 0
