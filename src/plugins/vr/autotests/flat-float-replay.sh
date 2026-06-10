#!/usr/bin/env bash
# Auto-float replay (M3, issue #26): a window whose host output's pseudomirror
# is detached from the scene must promote itself to vr-floating instead of
# rendering into a dead subtree ("no app windows in VR" baseline bug), and the
# promotion is one-way — re-showing the mirror must NOT snap it back.
#
# The mirror is detached via the test hook (parent=null), the same mechanism
# VOC-MIRROR-060's hideVirtualDisplay binding uses; that config path is pinned
# by the Virtual-T hidden-at-start assertion below.
#
# Covers: VOC-MIRROR-080 (auto-float on hidden host output: promotion of live
# windows AND windows born on an already-hidden output), placement via the
# shared allocator (VOC-PLACE-020 path for windows).
#
# Usage: flat-float-replay.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flat-float-replay.sh <build-bin-dir>}"

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

boot_flat_kwin "$BIN_DIR"
activate_vr

MIRRORS='flatScene.workspace.outputMirrors'

# VOC-MIRROR-060 wiring: the VR virtual screen's mirror is hidden by default
if ! vreval_wait "(!!$MIRRORS.outputMap[\"Virtual-T\"]).toString()" "true" 15 > /dev/null; then
    fail "no pseudomirror tracked for Virtual-T (outputs: $(vreval "Object.keys($MIRRORS.outputMap).join(\",\")"))"
fi
assert_eq "$(vreval "($MIRRORS.outputMap[\"Virtual-T\"].parent === null).toString()")" \
    "true" "Virtual-T mirror hidden at start (hideVirtualDisplay default)"

spawn_client() { # <name> -> sets CPID, echoes nothing
    cat > "$HOME/$1.qml" <<EOF
import QtQuick
Window { visible: true; width: 320; height: 240; title: "$1"; color: "purple" }
EOF
    env -u QT_PLUGIN_PATH -u QT_FORCE_STDERR_LOGGING \
        WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        setsid "$QML_BIN" "$HOME/$1.qml" > "$HOME/$1.log" 2>&1 &
    CPID=$!
}

# --- baseline: a client on a visible mirror stays in screen state ---
base=$(vreval 'flatScene.workspace.appWindows.count')
spawn_client clientA
APID=$CPID
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 1))" 15 > /dev/null; then
    echo "--- clientA.log:"; cat "$HOME/clientA.log"
    fail "clientA never appeared (count stuck at $(vreval 'flatScene.workspace.appWindows.count'), base $base)"
fi
A="flatScene.workspace.appWindows.objectAt($base)"
HOST=$(vreval "$A.client.output.name")
sleep 1   # let deferred maybeAutoFloat (Component.onCompleted) settle
assert_eq "$(vreval "$A.client.vr.toString()")" "false" "window on visible mirror ($HOST) stays in screen state"
assert_eq "$(vreval "$A.hostOutputHidden.toString()")" "false" "hostOutputHidden false while mirror attached"

# --- VOC-MIRROR-080: detaching the host mirror promotes the window ---
vreval "$MIRRORS.outputMap[\"$HOST\"].parent = null; \"ok\"" > /dev/null
if ! vreval_wait "$A.client.vr.toString()" "true" 10 > /dev/null; then
    fail "window never promoted to vr after its mirror detached (hostOutputHidden=$(vreval "$A.hostOutputHidden.toString()"))"
fi
echo "ok: window promoted to vr=true when host mirror detached"
assert_eq "$(vreval "($A.parent !== null).toString()")" "true" "floated window is in a live subtree"

# Allocator placement gave it real size and a non-degenerate pose
w=$(vreval "$A.itemSize.width.toFixed(0)")
[ "${w:-0}" != "0" ] || fail "floated window has zero itemSize — not placed"
dist=$(vreval "$A.scenePosition.length().toFixed(0)")
[ "${dist:-0}" != "0" ] || fail "floated window sits at the scene origin — findFreePosition never ran"
echo "ok: floated window placed (itemSize.width=$w, |scenePosition|=$dist)"

# --- birth on a hidden output: a new client must float from the start ---
spawn_client clientB
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$((base + 2))" 15 > /dev/null; then
    echo "--- clientB.log:"; cat "$HOME/clientB.log"
    fail "clientB never appeared"
fi
B="flatScene.workspace.appWindows.objectAt($((base + 1)))"
if ! vreval_wait "$B.client.vr.toString()" "true" 10 > /dev/null; then
    fail "window born on hidden output never promoted to vr"
fi
echo "ok: window born on hidden output floats from the start"

# --- one-way promotion: re-attaching the mirror must not snap them back ---
vreval "$MIRRORS.outputMap[\"$HOST\"].parent = $MIRRORS; \"ok\"" > /dev/null
sleep 1
assert_eq "$(vreval "$A.client.vr.toString()")" "true" "promoted window stays floating after mirror re-shown"
assert_eq "$(vreval "$B.client.vr.toString()")" "true" "born-floating window stays floating after mirror re-shown"

# Cleanup: client exit removes the windows
kill -TERM -"$APID" -"$CPID" 2>/dev/null
if ! vreval_wait 'flatScene.workspace.appWindows.count' "$base" 15 > /dev/null; then
    fail "client windows did not leave on exit"
fi
echo "ok: windows left the scene on client exit"

echo "PASS: auto-float replay — promotion on detach, birth-on-hidden, one-way, placement"
exit 0
