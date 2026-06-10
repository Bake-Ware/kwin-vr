# Test Baseline

First-ever test run on this fork: 2026-06-09, commit `18cd930`-era `main`,
Arch (CachyOS) host, Qt 6.11.1, `QT_QPA_PLATFORM=offscreen`, `dbus-run-session`,
run as root alongside a live Plasma session (which matters — see classes below).

**Headline: 142/161 green** (67/68 unit, 75/93 integration) on a fork whose tests
had never been built. The 19 failures triage into four classes; none is a confirmed
VR regression so far, but the DRM trio is a real suspect until proven otherwise.

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

## Class 4 — Reproducible failure, VR-patch suspect ⚠

| Test | Failure | Why suspect |
|---|---|---|
| `kwin-testDrm`, `kwin-testDrmLegacy`, `kwin-testDrmNoModifiers` | `initTestCase` fails at `QCOMPARE(workspace()->applyOutputConfiguration(cfg), OutputConfigurationError::None)` (drm_test.cpp:347), reproducible in direct rerun | `applyOutputConfiguration` / output-config path is exactly where the VR leasable-output core patches live (`doc/CORE_PATCHES.md`). BUT: these tests open real `/dev/dri` while a live session holds DRM master, which can also explain the failure. |

**Action (ticketed):** rerun the DRM trio on an idle machine or with the vkms
kernel module and no live session. If they still fail, bisect against
`upstream/6.6.3_vr` — that distinguishes "VR patch broke output config" from
"can't modeset under a live session".

## VR-owned suites: environment-conditional asserts

| Test | Condition | Behavior |
|---|---|---|
| `kwinvr-testFlatBoot` | No RHI scene graph (CI container has no `/dev/dri` → software compositing → "Qt Quick 3D is not functional") | Frame-render assertion SKIPs on that exact log marker only; boot/DBus/QML-error asserts still apply. Hard assertion anywhere GL exists. Tracked in #38. |
| `kwinvr-testFlatReplay` | Qt 6 `qml` runtime missing | Wayland-client placement section SKIPs (a Qt 5 `qml` in PATH is rejected — it loads nothing on versionless imports); interaction asserts still apply. |
| `kwinvr-testFlatHudReplay` | Qt 6 `qml` runtime missing, or `org.kde.layershell` QML module not installed (layer-shell-qt) | Whole test SKIPs — it has no client-free section; the #17 lift math stays pinned by `kwinvr-testQmlLogic` regardless. |

## Reproduce

```bash
cmake -B build -DBUILD_TESTING=ON && cmake --build build -j$(nproc)
export QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=$(mktemp -d)
dbus-run-session bash ci/run-unit-tests.sh build        # 68 tests
dbus-run-session bash ci/run-integration-tests.sh build # 75 required tests
ctest --test-dir build -R 'kwinvr-'                     # VR-owned suites
```
