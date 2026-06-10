#!/usr/bin/env bash
# HUD overlay replay (M3, issue #17): a real layer-shell dock client lands on
# the HUD, opens an xdg-popup, and the popup must sit strictly closer to the
# viewer than the dock it belongs to — the transient-occlusion regression
# (popups z-fighting / drawing through their parents on the HUD surface).
#
# Covers: HudWindowFilter admission (dock + transient chain), VrHudWindow
# transientDepth lift. Curved-path math is pinned by kwinvr-testQmlLogic;
# this exercises the live (flat-curvature) path end-to-end.
#
# Usage: flat-hud-replay.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flat-hud-replay.sh <build-bin-dir>}"

# Needs the Qt 6 qml runtime and the LayerShellQt QML module.
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
if [ ! -e /usr/lib/qt6/qml/org/kde/layershell/qmldir ]; then
    echo "SKIP: org.kde.layershell QML module not installed (layer-shell-qt)"
    exit 0
fi

boot_flat_kwin "$BIN_DIR"
activate_vr

assert_eq "$(vreval 'flatScene.workspace.hudWindows.count')" "0" "HUD empty at start"

# Dock via layer-shell (scope "dock" → WindowType::Dock → HudWindowFilter),
# with an xdg-popup over the layer surface → transient child of the dock.
# The popup must be NON-grabbing (Qt.ToolTip): a grabbing xdg-popup needs an
# input serial, and nothing has clicked the headless dock — Controls' Popup
# fails with "Failed to create grabbing popup" and never maps.
cat > "$HOME/dock.qml" <<'EOF'
import QtQuick
import org.kde.layershell as LayerShell

Window {
    id: dock
    visible: true
    width: 600; height: 48
    color: "steelblue"

    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop

    Window {
        id: pop
        transientParent: dock
        flags: Qt.ToolTip | Qt.FramelessWindowHint   // grab-less xdg-popup
        visible: true
        x: 10; y: 10
        width: 200; height: 150
        color: "orange"
    }
}
EOF
env -u QT_PLUGIN_PATH \
    WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
    setsid "$QML_BIN" "$HOME/dock.qml" > "$HOME/dock.log" 2>&1 &
CPID=$!

# Dock + its popup both land on the HUD
if ! vreval_wait 'flatScene.workspace.hudWindows.count' "2" 15 > /dev/null; then
    echo "--- dock.log:"; cat "$HOME/dock.log"
    fail "dock + popup never landed on the HUD (count $(vreval 'flatScene.workspace.hudWindows.count'))"
fi
echo "ok: dock + popup landed on the HUD (count 2)"

# Identify them by transient depth and assert the #17 lift: the popup must
# sit strictly closer to the viewer (greater local z, flat curvature path).
read -r d0 d1 <<EOF2
$(vreval 'flatScene.workspace.hudWindows.objectAt(0).transientDepth') $(vreval 'flatScene.workspace.hudWindows.objectAt(1).transientDepth')
EOF2
case "$d0 $d1" in
    "0 1") DOCK=0; POP=1 ;;
    "1 0") DOCK=1; POP=0 ;;
    *) fail "unexpected transient depths: dock/popup = '$d0'/'$d1'" ;;
esac
echo "ok: transient depths resolved (dock=$d0... popup chain depth 1)"

dz=$(vreval "flatScene.workspace.hudWindows.objectAt($DOCK).position.z.toFixed(2)")
pz=$(vreval "flatScene.workspace.hudWindows.objectAt($POP).position.z.toFixed(2)")
closer=$(vreval "(flatScene.workspace.hudWindows.objectAt($POP).position.z > flatScene.workspace.hudWindows.objectAt($DOCK).position.z).toString()")
assert_eq "$closer" "true" "popup lifted toward viewer over its dock (dock z=$dz, popup z=$pz)"

# Cleanup: client exit must empty the HUD again
kill -TERM -"$CPID" 2>/dev/null
if ! vreval_wait 'flatScene.workspace.hudWindows.count' "0" 15 > /dev/null; then
    fail "HUD windows did not leave on client exit"
fi
echo "ok: HUD emptied on client exit"

echo "PASS: HUD replay — dock+popup admission, #17 transient lift, teardown"
exit 0
