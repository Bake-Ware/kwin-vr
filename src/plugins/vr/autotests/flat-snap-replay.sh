#!/usr/bin/env bash
# Stack-size replay (M3, issue #18): two real Wayland clients are floated in
# the 3D workspace and one is stack-committed onto the other. The stack must
# behave as one rigid container: the member matches the root's size at commit
# (VOC-SNAP-060) and KEEPS matching it — a later resize of the root propagates
# to the member, and a member resizing itself is snapped back to the root size
# (VOC-SNAP-150). Without that, layouts drift apart after any client resize.
#
# Usage: flat-snap-replay.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flat-snap-replay.sh <build-bin-dir>}"

# Needs the Qt 6 qml runtime (a Qt 5 `qml` loads nothing on versionless
# imports — see flat-replay.sh).
QML_BIN=""
for _c in /usr/lib/qt6/bin/qml "$(command -v qml6 2>/dev/null)" "$(command -v qml 2>/dev/null)"; do
    [ -n "$_c" ] && [ -x "$_c" ] || continue
    case "$("$_c" --version 2>/dev/null)" in
        *" 6."*) QML_BIN=$_c; break ;;
    esac
done
if [ -z "$QML_BIN" ]; then
    echo "SKIP: Qt 6 qml runtime not found"
    exit 0
fi

boot_flat_kwin "$BIN_DIR"
activate_vr

base=$(vreval 'flatScene.workspace.appWindows.count')

cat > "$HOME/root.qml" <<'EOF'
import QtQuick
Window { visible: true; width: 500; height: 400; title: "snap-root"; color: "green" }
EOF
cat > "$HOME/member.qml" <<'EOF'
import QtQuick
Window { visible: true; width: 320; height: 240; title: "snap-member"; color: "orange" }
EOF
env -u QT_PLUGIN_PATH -u QT_FORCE_STDERR_LOGGING \
    WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
    setsid "$QML_BIN" "$HOME/root.qml" > "$HOME/clients.log" 2>&1 &
CPID=$!
env -u QT_PLUGIN_PATH -u QT_FORCE_STDERR_LOGGING \
    WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
    setsid "$QML_BIN" "$HOME/member.qml" >> "$HOME/clients.log" 2>&1 &
CPID2=$!

if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 2))" 15 > /dev/null; then
    echo "--- clients.log:"; cat "$HOME/clients.log"
    fail "clients never landed in the workspace (count $(vreval 'flatScene.workspace.appWindows.count'), base $base)"
fi
echo "ok: both clients entered the scene (count $base -> $((base + 2)))"

# Resolve repeater indices by caption.
winexpr() { # winexpr <caption> → JS expression for that KwinApplicationWindow
    echo "(function(){const r=flatScene.workspace.appWindows; for(let i=0;i<r.count;i++){const w=r.objectAt(i); if(w&&w.client&&w.client.caption===\"$1\") return w} return null})()"
}
ROOTW=$(winexpr snap-root)
MEMBW=$(winexpr snap-member)
assert_eq "$(vreval "(!!$ROOTW).toString()")" "true" "root window resolved by caption"
assert_eq "$(vreval "(!!$MEMBW).toString()")" "true" "member window resolved by caption"

# Float both into the 3D workspace (drag-out path is VOC-PLACE; here we flip
# the state directly — stacking only applies to VR-floating windows).
vreval "$ROOTW.client.vr = true; $MEMBW.client.vr = true; \"ok\"" > /dev/null
assert_eq "$(vreval "($ROOTW.client.vr && $MEMBW.client.vr).toString()")" "true" "both windows VR-floating"

# Frame sizes include server-side decoration, so all asserts compare member
# frame to root frame rather than to absolute pixel numbers.
SIZES="$ROOTW.client.frameGeometry.width + 'x' + $ROOTW.client.frameGeometry.height + ' / ' + $MEMBW.client.frameGeometry.width + 'x' + $MEMBW.client.frameGeometry.height"
FRAMES_MATCH="($MEMBW.client.frameGeometry.width === $ROOTW.client.frameGeometry.width && $MEMBW.client.frameGeometry.height === $ROOTW.client.frameGeometry.height).toString()"

# --- VOC-SNAP-060: stack commit resizes member to root's full size ---
vreval "flatScene.workspace.snap._commitSnap($MEMBW, $ROOTW, 5); \"ok\"" > /dev/null
assert_eq "$(vreval "($MEMBW.stackedOnto === $ROOTW).toString()")" "true" "member stackedOnto root"
assert_eq "$(vreval "$MEMBW.stackIndex")" "1" "member stackIndex"
if ! vreval_wait "$FRAMES_MATCH" "true" 10 > /dev/null; then
    fail "stack commit did not resize member to root size (root/member: $(vreval "$SIZES"))"
fi
echo "ok: stack commit resized member to root frame size ($(vreval "$SIZES"))"

# --- VOC-SNAP-150 (#18): root resize propagates to stacked member ---
rw0=$(vreval "$ROOTW.client.frameGeometry.width")
vreval "KwinVrHelpers.windowResize($ROOTW.client, 140, 80); \"ok\"" > /dev/null
if ! vreval_wait "$ROOTW.client.frameGeometry.width" "$((rw0 + 140))" 10 > /dev/null; then
    fail "root never resized (root/member: $(vreval "$SIZES"))"
fi
if ! vreval_wait "$FRAMES_MATCH" "true" 10 > /dev/null; then
    fail "#18 drift: member did not follow root resize (root/member: $(vreval "$SIZES"))"
fi
echo "ok: member followed root resize ($(vreval "$SIZES"))"

# --- VOC-SNAP-150 (#18): member self-resize snaps back to container size ---
vreval "KwinVrHelpers.windowResize($MEMBW.client, -200, -100); \"ok\"" > /dev/null
sleep 2   # let the configure round-trip land before checking convergence
if ! vreval_wait "$FRAMES_MATCH" "true" 10 > /dev/null; then
    fail "#18 drift: member self-resize was not snapped back to root size (root/member: $(vreval "$SIZES"))"
fi
echo "ok: member self-resize snapped back to container size ($(vreval "$SIZES"))"

# Cascade pose intact: member sits at (+step, -step, +step) in root-local
# coords (step = zSurfaceMarginTop) regardless of the resizes above.
off=$(vreval "(function(){const p=$ROOTW.mapPositionFromScene($MEMBW.scenePosition); const s=KWinVRConfig.zSurfaceMarginTop; return (Math.abs(p.x-s)<0.05 && Math.abs(p.y+s)<0.05 && Math.abs(p.z-s)<0.05).toString()})()")
assert_eq "$off" "true" "cascade offset unchanged through resizes"

# Detach clears stack state (and must stop the size-follow).
vreval "flatScene.workspace.snap._detachFromStack($MEMBW); \"ok\"" > /dev/null
assert_eq "$(vreval "($MEMBW.stackedOnto === null).toString()")" "true" "member detached"

# Teardown
kill -TERM -"$CPID" 2>/dev/null
kill -TERM -"$CPID2" 2>/dev/null
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$base" 15 > /dev/null; then
    fail "windows did not leave on client exit"
fi
echo "ok: scene emptied on client exit"

echo "PASS: stack replay — commit size match, #18 size propagation, cascade pose, teardown"
exit 0
