#!/usr/bin/env bash
# Focus-pull replay (M3, #26 follow-up): activating a far-off vr-floating
# window must pull it to the sibling-average depth along its cam→window ray,
# face it to the user, and pan the world (followMode.focusOn with an explicit
# camera — the property binding is null-gated whenever followEnabled is off,
# which is the default) until it is centered. Deactivating it must restore
# its saved pose.
#
# Trigger is the real one: KWin activation edges (a new client steals focus,
# killing it hands focus back), not a direct pullAppWinForward() call.
#
# Covers: VOC-FOCUS-010 (pull + pan on activation), VOC-FOCUS-020 (pose
# restore on deactivation). The C++ pan override internals (teardown on
# destroy/unregister, no-op in FOV) are pinned by kwinvr-testVrFollowMode.
#
# Usage: flat-focus-replay.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flat-focus-replay.sh <build-bin-dir>}"

# Needs the Qt 6 qml runtime for real Wayland clients.
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

# followEnabled=false makes the scenario deterministic (normal follow mode
# would legitimately re-pan the world toward the restored window, masking
# the restore) AND pins the very case focusOn exists for: the followMode
# camera binding is null the whole time, so only the explicit camera handed
# to focusOn() can drive the pan (the #26 archive bug).
VRTEST_EXTRA_CONFIG=$'followEnabled=false\n'
boot_flat_kwin "$BIN_DIR"
activate_vr

base=$(vreval 'flatScene.workspace.appWindows.count')

spawn_client() { # <caption> -> sets CPID
    cat > "$HOME/$1.qml" <<EOF
import QtQuick
Window { visible: true; width: 320; height: 240; title: "$1"; color: "teal" }
EOF
    env -u QT_PLUGIN_PATH -u QT_FORCE_STDERR_LOGGING \
        WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        setsid "$QML_BIN" "$HOME/$1.qml" > "$HOME/$1.log" 2>&1 &
    CPID=$!
}

winexpr() { # winexpr <caption> → JS expression for that KwinApplicationWindow
    echo "(function(){const r=flatScene.workspace.appWindows; for(let i=0;i<r.count;i++){const w=r.objectAt(i); if(w&&w.client&&w.client.caption===\"$1\") return w} return null})()"
}

# --- subject: one vr-floating window, parked far behind the viewer ---
spawn_client focus-subject
APID=$CPID
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 1))" 15 > /dev/null; then
    echo "--- focus-subject.log:"; cat "$HOME/focus-subject.log"
    fail "subject client never appeared (count $(vreval 'flatScene.workspace.appWindows.count'), base $base)"
fi
A=$(winexpr focus-subject)
assert_eq "$(vreval "(!!$A).toString()")" "true" "subject window resolved by caption"

vreval "$A.client.vr = true; \"ok\"" > /dev/null
assert_eq "$(vreval "$A.client.vr.toString()")" "true" "subject is VR-floating"
assert_eq "$(vreval "$A.client.active.toString()")" "true" "freshly spawned subject is the active window"

# Park it far away and BEHIND the camera: out of follow FOV so the pan must
# run, and far off the sibling-average depth so the slide is observable.
vreval "KwinVrHelpers.setNodePositionFromScene($A, Qt.vector3d(0, 0, 600)); \"ok\"" > /dev/null
FARPOS='Qt.vector3d(0, 0, 600)'
assert_eq "$(vreval "($A.scenePosition.minus($FARPOS).length() < 1).toString()")" \
    "true" "subject parked at the far pose"

# --- a second client steals focus; no pull existed, so nothing moves ---
spawn_client focus-stealer
SPID=$CPID
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 2))" 15 > /dev/null; then
    echo "--- focus-stealer.log:"; cat "$HOME/focus-stealer.log"
    fail "stealer client never appeared"
fi
if ! vreval_wait "$A.client.active.toString()" "false" 10 > /dev/null; then
    fail "stealer never took focus from the subject"
fi
assert_eq "$(vreval "($A.scenePosition.minus($FARPOS).length() < 1).toString()")" \
    "true" "deactivation without a prior pull moves nothing"
assert_eq "$(vreval '(flatScene.workspace._focusedPullPose === null).toString()')" \
    "true" "no pull pose saved for a vr=false activation"

# --- VOC-FOCUS-010: focus comes back → pull + pan ---
kill -TERM -"$SPID" 2>/dev/null
if ! vreval_wait "$A.client.active.toString()" "true" 15 > /dev/null; then
    fail "subject never re-activated after the stealer exited"
fi
if ! vreval_wait "(flatScene.workspace._focusedPullPose !== null && flatScene.workspace._focusedPullPose.window === $A).toString()" "true" 10 > /dev/null; then
    fail "activation did not save a pull pose for the subject"
fi
# Slide: distance to camera == sibling-average depth, which with no other
# floating windows is the configured default distance.
DIST_EXPR="$A.scenePosition.minus(flatScene.workspace.camera.scenePosition).length()"
WANT=$(vreval 'flatScene.workspace.distance')
near=$(vreval "(Math.abs($DIST_EXPR - flatScene.workspace.distance) < 2).toString()")
assert_eq "$near" "true" "subject slid to default depth (|cam→win| $(vreval "$DIST_EXPR.toFixed(1)"), want $WANT)"
# Pan: the world rotates until the subject sits inside stop-FOV of the camera
# — even though followMode.camera is null (followEnabled defaults off); the
# explicit camera handed to focusOn() must drive it (the #26 archive bug).
CENTERED="(function(){const cam=flatScene.workspace.camera; const p=cam.mapPositionFromScene($A.scenePosition); if (p.z >= 0) return \"behind\"; const h=Math.abs(Math.atan2(p.x, -p.z)) * 180 / Math.PI; const v=Math.abs(Math.atan2(p.y, -p.z)) * 180 / Math.PI; return (h <= KWinVRConfig.followStopFovH + 2 && v <= KWinVRConfig.followStopFovV + 2).toString()})()"
if ! vreval_wait "$CENTERED" "true" 30 > /dev/null; then
    fail "world pan never centered the subject (camera-local: $(vreval "JSON.stringify(flatScene.workspace.camera.mapPositionFromScene($A.scenePosition))"))"
fi
echo "ok: activation pulled the subject to depth and panned it into stop-FOV"

# --- VOC-FOCUS-020: defocus restores the saved pose ---
spawn_client focus-third
TPID=$CPID
if ! vreval_wait "$A.client.active.toString()" "false" 15 > /dev/null; then
    echo "--- focus-third.log:"; cat "$HOME/focus-third.log"
    fail "third client never took focus"
fi
if ! vreval_wait "($A.scenePosition.minus($FARPOS).length() < 1).toString()" "true" 10 > /dev/null; then
    fail "deactivation did not restore the far pose (now at $(vreval "JSON.stringify($A.scenePosition)"))"
fi
assert_eq "$(vreval '(flatScene.workspace._focusedPullPose === null).toString()')" \
    "true" "pull pose cleared after restore"
echo "ok: deactivation restored the saved pose"

# Cleanup: client exit removes the windows
kill -TERM -"$APID" -"$TPID" 2>/dev/null
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$base" 15 > /dev/null; then
    fail "client windows did not leave on exit"
fi

echo "PASS: focus-pull replay — pull+pan on activation, pose restore on defocus"
exit 0
