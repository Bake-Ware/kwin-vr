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
| `kwin-testMockDrm` (unit, **VR series' own lease test**) | aborted at 312s in batch; 18/18 pass in 136ms direct. **Also SIGSEGVs in the CI container** (SEGV_MAPERR at offset 0x18 right after initTestCase — null deref, likely assumes `/dev/dri` exists despite the mock). Quarantined in `ci/unit-quarantine.txt`; ticketed to make the mock truly device-free, since this is the test guarding the DRM-lease feature. |
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

## Reproduce

```bash
cmake -B build -DBUILD_TESTING=ON && cmake --build build -j$(nproc)
export QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=$(mktemp -d)
dbus-run-session bash ci/run-unit-tests.sh build        # 68 tests
dbus-run-session bash ci/run-integration-tests.sh build # 75 required tests
ctest --test-dir build -R 'kwinvr-'                     # VR-owned suites
```
