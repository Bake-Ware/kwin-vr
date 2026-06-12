# Test Baseline

First-ever test run on this fork: 2026-06-09, commit `18cd930`-era `main`,
Arch (CachyOS) host, Qt 6.11.1, `QT_QPA_PLATFORM=offscreen`, `dbus-run-session`,
run as root alongside a live Plasma session (which matters — see classes below).

**Headline: 142/161 green** (67/68 unit, 75/93 integration) on a fork whose tests
had never been built. The 19 failures triage into four classes; **none is a
VR regression** — the last suspect (the DRM trio) was cleared by A/B on idle
hardware 2026-06-12 (see Class 4).

CI policy: unit set (`ci/run-unit-tests.sh`) + non-quarantined integration set
(`ci/run-integration-tests.sh`) are **required**. The quarantine list is
`ci/integration-quarantine.txt`; every entry must appear in a class table below.
Un-quarantining is progress. New tests are required by default.

## Class 1 — Pass when run individually (batch contention)

Verified by direct rerun. The batch run executes serially but contends with the
live session (DRM access, session bus). Quarantined until CI proves them stable
in a container; expected green there.

| Test | Evidence |
|---|---|
| `kwin-testMockDrm` (unit, **VR series' own lease test**) | **Un-quarantined (#36, CI-required).** Was: aborted at 312s in batch, SIGSEGV in the CI container (`findPrimaryDevice` returned null with no `/dev/dri`, then derefed). The mock is now truly device-free — the GPU "node" is `/dev/null`, with `gbm_create_device`/`drmGetDeviceNameFromFd2`/`drmIsMaster` interposed alongside the drm mocks (test built with `ENABLE_EXPORTS` so interposition reaches calls from libkwin.so). 18/18 in ~160ms, verified with `/dev/dri` bind-mounted empty; it no longer touches real DRM at all, so the batch-contention abort mode is gone too. |
| `kwin-testXdgShellWindow` | 120s timeout in batch; 68/69 in 12s direct (the 1 fail is `testAppMenu`, which needs `dbus-run-session` — green with it) |
| `kwin-testLockScreen` | 120s timeout in batch; 20/20 in 63s direct |
| `kwin-testOutputChanges` | 120s timeout in batch; 92/92 in 14s direct |
| `kwin-testPlasmaWindow` | 120s timeout in batch; 7/7 in 3s direct |
| `kwin-testX11Window` | 120s timeout in batch; 188/188 in 8s direct |
| `kwin-testActivities` | 120s timeout in batch; 3/3 in 0.4s direct |

All Class 1 entries are now verified: **zero real failures** — consecutive serial
runs sharing one `XDG_RUNTIME_DIR`/session-bus appear to poison later tests.
Worth trying per-test fresh `XDG_RUNTIME_DIR` in the runner scripts; if that
stabilizes them, this whole class un-quarantines.

## Class 2 — Environment: effect plugins not loadable at runtime

`effects->loadEffect(<other effect>)` returns FALSE — the test compositor can't
locate the *other* effect plugins (plugin path), while its own statically-linked
effect works. Needs `QT_PLUGIN_PATH`/install-tree investigation; upstream CI runs
these green.

`kwin-testSlidingPopups`, `kwin-testToplevelOpenCloseAnimation`,
`kwin-testDesktopSwitchingAnimation`, `kwin-testMinimizeAnimation`,
`kwin-testDontCrashReinitializeCompositor`

**CI-container only:** `kwin-testDontCrashGlxgears` and
`kwin-testDebugConsole` pass locally but `glxgears.waitForStarted()`
fails instantly in the Actions container even with mesa-demos installed
(exec-time failure, not missing window). The workflow's "Environment
diagnostics" step records `which glxgears` per run for triage.

## Class 3 — Environment: missing device/service in this run

| Test | Needs |
|---|---|
| `kwin-testGameController` | uinput device creation (all spy waits time out) |
| `kwin-testScreencasting` | working PipeWire stream (null frame image) |
| `kwin-testInputMethod` | input-method service |
| `kwin-testFifo` | timing-sensitive (24Hz frame pacing spies) — likely flaky under load |

## Class 4 — ~~VR-patch suspect~~ RESOLVED: not a VR regression (2026-06-12)

| Test | Original failure | Verdict |
|---|---|---|
| `kwin-testDrm`, `kwin-testDrmLegacy`, `kwin-testDrmNoModifiers` | `initTestCase` fails at `applyOutputConfiguration` (drm_test.cpp:347) | **Not VR.** Substrate-sensitive upstream tests; see evidence below. Remain quarantined as environment-dependent. |

**Verification run (idle ThinkPad i5-6200U/HD 520, no session, root + `CI=true`
noop session, 2026-06-12):**

- The original :347 failure (`OutputConfigurationError::Unknown`) was DRM-master
  acquisition: without a seat session (or with any live compositor holding the
  node) every atomic commit gets EACCES. With a true idle device it disappears.
- `testDrmLegacy`: **full pass** on both i915 and vkms.
- `testDrm` on i915: new failure — after disabling the 2nd output its connector
  still reports a CRTC (drm_test.cpp:356). **Identical failure with all VR DRM
  backend patches reverted** (A/B with a reverted `libkwin.so` on the same
  hardware) — that is the exonerating data point.
- `testDrm` on vkms (same machine): fails the *opposite* assert — the enabled
  output has *no* CRTC. `testDrmNoModifiers` on vkms gets through 8/11 and fails
  only direct-scanout scaling baselines. The failure set is different on every
  substrate; upstream CI green presumably depends on their exact vkms/kernel.

**Gotchas for anyone re-running this:**
- The test framework only uses the noop session when `CI=true` is set; without
  it, a logind session without a seat can't get DRM master (EACCES everywhere).
- A live KWin session (even on another GPU) hotplug-grabs a freshly loaded vkms
  device and holds master — vkms is only uncontended on a machine with no
  compositor running at all.

## Class 5 — Intermittent CI-container flake

Passes in most CI runs; fails occasionally on changes that cannot affect it.
Quarantined to keep the required set honest; un-quarantine after the flake is
understood (each entry has a tracking issue).

| Test | Evidence |
|---|---|
| `kwin-testXwaylandInput` | Fast double-fail (~0.3s, fails the runner's retry too) of `testPointerEnterLeaveSsd` at `'!window->readyForPainting()' returned FALSE`, with "Failed to initialize glamor, falling back to sw" in the log — runs 27261660727 (main, 2026-06-10) and 27267626577 (stale-socket PR, same day, VR-plugin-only diff). Same test green in ≥5 other runs that day on sibling changes. Smells like Xwayland/glamor startup timing in the container. Tracking issue: #48. |

## VR-owned suites: environment-conditional asserts

| Test | Condition | Behavior |
|---|---|---|
| `kwinvr-testFlatBoot` | No RHI scene graph (no `/dev/dri` → software compositing → "Qt Quick 3D is not functional") | Frame-render assertion SKIPs on that exact log marker only; boot/DBus/QML-error asserts still apply. Hard assertion anywhere GL exists — **including CI since #38**: the workflow loads `vgem` (or `vkms` — the azure kernels ship only vkms; kwin's virtual backend special-cases both to use the primary node) on the runner host and passes `/dev/dri` into the container, so mesa's `kms_swrast` gives the virtual backend a real GL context. CI also sets `KWINVR_REQUIRE_RHI=1`, which turns the SKIP into a FAIL — a green CI run therefore *proves* the frame-render assertion executed. |
| `kwinvr-testFlatReplay` | Qt 6 `qml` runtime missing | Wayland-client placement section SKIPs (a Qt 5 `qml` in PATH is rejected — it loads nothing on versionless imports); interaction asserts still apply. |
| `kwinvr-testFlatHudReplay` | Qt 6 `qml` runtime missing, or `org.kde.layershell` QML module not installed (layer-shell-qt) | Whole test SKIPs — it has no client-free section; the #17 lift math stays pinned by `kwinvr-testQmlLogic` regardless. |
| `kwinvr-testFlatSnapReplay` | Qt 6 `qml` runtime missing | Whole test SKIPs — it is built around two real Wayland clients. |
| `kwinvr-testFlatFloatReplay` | Qt 6 `qml` runtime missing | Whole test SKIPs — it is built around two real Wayland clients. The #26 allocator cone cap stays pinned by `kwinvr-testSpaceAllocator3D` regardless. |
| `kwinvr-testFlatFocusReplay` | Qt 6 `qml` runtime missing | Whole test SKIPs — it drives real activation edges with three Wayland clients (focus pull VOC-FOCUS-010/020). Boots with `followEnabled=false` so the pan can only come from `focusOn`'s explicit camera. The C++ pan override itself stays pinned by `kwinvr-testVrFollowMode` (unit, never skips). |

## Reproduce

```bash
cmake -B build -DBUILD_TESTING=ON && cmake --build build -j$(nproc)
export QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=$(mktemp -d)
dbus-run-session bash ci/run-unit-tests.sh build        # 68 tests
dbus-run-session bash ci/run-integration-tests.sh build # 75 required tests
ctest --test-dir build -R 'kwinvr-'                     # VR-owned suites
```
