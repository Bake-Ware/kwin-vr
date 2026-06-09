# Salvage Ledger

Features that exist only on archived branches (preserved under `archive/*` tags) and must
be re-implemented on `main`. The old branches are on the incompatible 6.5.5 base — salvage
means **re-implement using the archived code as reference**, never wholesale merge.

Each row is tracked by the linked GitHub issue (filed 2026-06-09); strike the row
when the feature lands on `main` with tests.

| Feature | Reference commits | Archive tag | Target | Issue |
|---|---|---|---|---|
| Profile system + custodian lessons (stale-socket detection, deactivation ordering, output layout) | `fc67e6e2f2`, `962f190382` | `archive/stabilization` | M3 | #23 |
| Profile-driven hot-plug output monitoring (replaces 15s timer) | `a892c6cdd3` | `archive/performance_optimization` | M3 | #24 |
| WindowGroup data model + registry (dock/stack scaffold) | `acba70807b` | `archive/6.6.3_vr_bake_pre_rollback` | M3 | #25 |
| Auto-float windows when host output hidden + focus pull/pan | `95947c85b6` | `archive/6.6.3_vr_bake_pre_rollback` | M3 | #26 |
| MangoHud-style sysinfo HUD (FPS/CPU/GPU/RAM) → perf regression harness | `37a04b3060` | `archive/performance_optimization` | M4 | #27 |
| WMR/WiVRn init scripts, udev rules, systemd units (extras/vr-headset-init, wivrn-watch) | tree on tag | `archive/stabilization` | M4 | #28 |
| Immersive mode, head-as-mouse cursor lock, phantom cursor fix | `5d16591c03` | `archive/eye_tracking` | M5 | #29 |
| IR-camera eye tracking (gaze_mouse.py, pye3d) as a ray provider | `5f181c6764` | `archive/eye_tracking` | M5 | #30 |
| Mali-G610 locked-60fps perf pass | `853949aa1f` | `archive/performance_optimization` | M6 | #31 |
| Vulkan RHI dmabuf import fix (+ hybrid-GPU hardening) | `c0e5fd49dc` | `archive/performance_optimization` | M6 | #32 |
| Machine-portable installer + manifest-based uninstaller (extras/install/) | `bbef29c353`, `962f190382` | `archive/stabilization` | M8 | #33 |
| Orange Pi 5B install guide + system config files | `b113589031`, `3210237960` | `archive/performance_optimization` | M8 | #34 |
| Vignette + PIP (HUD-style picture-in-picture, window controls) | `d585f073f2`, `d04059b263` | `archive/6.5.5_vr` | backlog | #35 |

Already ported directly in M1 (docs, no re-implementation needed):
- `ARCHITECTURE.md` → `doc/ARCHITECTURE_PROFILES.md` (profile-matching contract)
- `extras/DESIGN-multi-hmd.md` → `doc/DESIGN_MULTI_HMD.md` (roles model; spectator-2d = flat-monitor mode)

Browse archived code without checking it out:
```bash
git show archive/stabilization:extras/install/build.sh
git ls-tree -r --name-only archive/eye_tracking | grep gaze
```
