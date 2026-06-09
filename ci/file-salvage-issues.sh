#!/usr/bin/env bash
# One-shot: file the salvage-ledger issues from doc/SALVAGE_LEDGER.md.
# Requires: gh auth login. Safe to re-run only after checking for duplicates.
set -euo pipefail

repo="Bake-Ware/kwin-vr"

file() { # title, milestone-label, body
    gh issue create --repo "$repo" --title "$1" --label salvage --body "$3

---
Target milestone: **$2** (roadmap). Re-implement using the archived code as
reference — never wholesale merge (incompatible 6.5.5 base).
Tracked in doc/SALVAGE_LEDGER.md."
}

gh label create salvage --repo "$repo" --color B60205 \
    --description "Feature stranded on an archived branch, to be re-implemented" 2>/dev/null || true

file "Salvage: profile system + custodian lessons (stale-socket detection, deactivation ordering)" M3 \
"Reference: \`fc67e6e2f2\`, \`962f190382\` on \`archive/stabilization\`.
Custodian daemon itself is retired (DRM leasing replaced it) — salvage the race-condition
lessons and the device-agnostic profile system (see doc/ARCHITECTURE_PROFILES.md) into the
current lease/startup path. Also kills the hardcoded >=3840px SBS heuristic."

file "Salvage: profile-driven hot-plug output monitoring" M3 \
"Reference: \`a892c6cdd3\` on \`archive/performance_optimization\`.
Replaced a 15s polling timer with profile-driven hot-plug monitoring. Current line has no
hot-plug story for glasses connect/disconnect."

file "Salvage: WindowGroup data model + registry (dock/stack scaffold)" M3 \
"Reference: \`acba70807b\` on \`archive/6.6.3_vr_bake_pre_rollback\`.
Scaffold for issue #14 dock/stack. See doc/DOCK_AND_STACK_WIP.md and VOC-SNAP-* statuses
in doc/VOCABULARY.md for what's still WIP."

file "Salvage: auto-float windows when host output hidden + focus pull/pan" M3 \
"Reference: \`95947c85b6\` on \`archive/6.6.3_vr_bake_pre_rollback\`."

file "Salvage: sysinfo HUD (FPS/CPU/GPU/RAM) as perf regression harness" M4 \
"Reference: \`37a04b3060\` on \`archive/performance_optimization\`.
MangoHud-style overlay. M4 extends it with frame-time CSV dump under a flag — becomes the
automated perf regression gate in M6."

file "Salvage: WMR/WiVRn init scripts, udev rules, systemd units" M4 \
"Reference: tree on \`archive/stabilization\` under \`extras/\` (vr-headset-init/, udev/,
systemd/). Browse: \`git ls-tree -r --name-only archive/stabilization extras/\`.
Feeds the M4 runtime-profile work (Monado-direct / WiVRn-network / flat)."

file "Salvage: immersive mode, head-as-mouse cursor lock, phantom cursor fix" M5 \
"Reference: \`5d16591c03\` on \`archive/eye_tracking\`."

file "Salvage: IR-camera eye tracking (gaze_mouse.py / pye3d) as a ray provider" M5 \
"Reference: \`5f181c6764\` on \`archive/eye_tracking\`.
In the M5 input abstraction, eye gaze is just another ray provider; gaze_mouse.py is the
reference producer feeding a uinput/libei device."

file "Salvage: Mali-G610 locked-60fps perf pass" M6 \
"Reference: \`853949aa1f\` on \`archive/performance_optimization\`.
The proven potato-tier perf work (OPi 5B). Re-land on main against current QML scene."

file "Salvage: Vulkan RHI dmabuf import fix (+ hybrid-GPU hardening)" M6 \
"Reference: \`c0e5fd49dc\` on \`archive/performance_optimization\`."

file "Salvage: machine-portable installer + manifest-based uninstaller" M8 \
"Reference: \`bbef29c353\`, \`962f190382\` on \`archive/stabilization\` (extras/install/
modular deps/detect/build/configure/deploy/uninstall). Basis for the distro-agnostic
installer deliverable."

file "Salvage: Orange Pi 5B install guide + system config files" M8 \
"Reference: \`b113589031\`, \`3210237960\` on \`archive/performance_optimization\`."

file "Salvage: vignette + PIP (HUD-style picture-in-picture, window controls)" backlog \
"Reference: \`d585f073f2\`, \`d04059b263\` on \`archive/6.5.5_vr\`."

echo "All salvage issues filed."
