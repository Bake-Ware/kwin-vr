#!/usr/bin/env bash
# Flat-mode boot smoke test (M2): boots a real kwin_wayland --virtual with
# displayMode=Flat, activates VR over DBus, and asserts:
#   1. org.kde.kwinvr appears on the session bus
#   2. vrActive flips to true (no Monado / OpenXR loader involved)
#   3. the QML scene loads with zero type/load errors
#   4. a captured frame actually rendered (non-black at real geometry — the
#      black-screen regression class this fork was born fighting)
#   5. the compositor is still alive afterwards
# This pins the bug class where renderer-seam QML only fails at runtime load
# (e.g. "Unable to assign QQuick3DPerspectiveCamera to QQuick3DXrCamera").
#
# Usage: flatboot-smoke.sh <build-bin-dir>
set -u
. "$(dirname "$0")/vrtestlib.sh"
vrtest_reexec "$@"

BIN_DIR="${1:?usage: flatboot-smoke.sh <build-bin-dir>}"
boot_flat_kwin "$BIN_DIR"   # 1. on bus
activate_vr                 # 2. vrActive=true

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
    # Quick3D needs an RHI-backed scene graph; without /dev/dri kwin falls
    # back to software compositing and View3D renders nothing by design.
    # Skip ONLY on that exact marker — anywhere GL exists this stays a hard
    # assertion. CI sets KWINVR_REQUIRE_RHI=1 (#38: the workflow loads a
    # virtual DRM module on the runner host precisely so GL exists there),
    # which turns this skip into a failure: a green CI run then PROVES the
    # frame-render assertion ran, instead of silently degrading.
    if grep -q 'Qt Quick 3D is not functional' "$LOG"; then
        if [ "${KWINVR_REQUIRE_RHI:-0}" = 1 ]; then
            fail "no RHI scene graph, but KWINVR_REQUIRE_RHI=1 — GL was required in this environment (#38)"
        fi
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
