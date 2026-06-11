# Migrating a custodian-era (6.5.5-line) machine to the 6.6.3 line

The 6.5.5 line ran VR through an external orchestrator ("custodian") plus a
custom SDDM session that launched KWin from a build tree. The 6.6.3 line is a
**single compositor process**: the packaged `kwin_wayland` + VR plugin owns
detection, lease, activation, and Monado supervision; `org.kde.kwinvr` D-Bus is
the control surface. (Decision record: custodian is cut — see
`ARCHITECTURE_PROFILES.md` for the one principle that survives.)

A machine that ever ran the 6.5.5 line has leftovers that **silently defeat a
6.6.3 install**. Both failure modes below were hit in the field on the first
6.6.3 hardware deploy (2026-06-11); each looked like a code bug and was not.

## Trap 1 — stale `plasma-vr.desktop` session hijacks the binary

**Symptom:** package installs fine, but after reboot `pgrep -a kwin_wayland`
shows `kwin_wayland` running from a home-dir build tree (e.g.
`~/kwin-vr-build/kwin_wayland`), not `/usr/bin/kwin_wayland`. Deleting the
`plasma-kwin_wayland.service.d` override doesn't help — **it comes back every
login**.

**Mechanism:** the 6.5.5 installer added
`/usr/share/wayland-sessions/plasma-vr.desktop`, whose `Exec` runs a
`startplasma-vr.sh` from the build tree. That script (a) re-installs the
systemd override for `plasma-kwin_wayland.service` on *every* login and
(b) prepends the build tree to the session `PATH`/`QT_PLUGIN_PATH`/
`QML_IMPORT_PATH`, so even the packaged `kwin_wayland_wrapper` resolves the old
binary. SDDM remembers the session per-user in `/var/lib/sddm/state.conf`, so
the machine keeps choosing it forever.

**Fix:**

```sh
# remove the session entry (back it up if sentimental)
sudo rm /usr/share/wayland-sessions/plasma-vr.desktop
# remove the re-created override
rm -rf ~/.config/systemd/user/plasma-kwin_wayland.service.d
systemctl --user daemon-reload
# point SDDM's remembered session back at stock Plasma
sudo sed -i 's|Session=.*plasma-vr.desktop *|Session=/usr/share/wayland-sessions/plasma.desktop|' \
    /var/lib/sddm/state.conf
```

The stock "Plasma (Wayland)" session is fully VR-capable on the 6.6.3 line —
there is no separate VR session anymore.

**Verify:** after reboot, `pgrep -a kwin_wayland` shows
`/usr/bin/kwin_wayland`, and `busctl --user status org.kde.kwinvr` reports that
same PID.

## Trap 2 — `XRT_COMPOSITOR_FORCE_WAYLAND=1` in the Monado base unit

**Symptom:** VR activates (head tracking drives the cursor), KWin marks the
glasses output leasable, but the glasses show the desktop/taskbar and a black
"Monado" window appears on the monitor. This is the classic black-screen mode
(`NVIDIA_VR_SETUP.md` env table).

**Mechanism:** the custodian-era `~/.config/systemd/user/monado.service` sets
`Environment=XRT_COMPOSITOR_FORCE_WAYLAND=1` (Wayland-*window* compositor
target). **Adding `XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT=1` in a drop-in does not
fix it** — systemd merges `Environment=` across unit + drop-ins, Monado sees
both flags, and window mode wins. Monado then renders into a desktop window
instead of requesting the DRM lease, even though the lease is on offer.

**Fix:** rewrite the base unit (one source of truth, no drop-ins) per the
reference unit in `NVIDIA_VR_SETUP.md`. The required line is

```ini
Environment=XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT=1
```

and `XRT_COMPOSITOR_FORCE_WAYLAND` must not appear anywhere in
`systemctl --user cat monado.service` output. On weak iGPUs (e.g. Intel
HD 520) also set `XRT_COMPOSITOR_SCALE_PERCENTAGE=100` — the 140% default
exceeds panel-link bandwidth.

**Verify:**

```sh
systemctl --user show monado.service -p Environment
# must contain FORCE_WAYLAND_DIRECT=1 and must NOT contain FORCE_WAYLAND=1
```

(Issue #50 tracks teaching `ensureMonadoRunning()` to detect this poison
itself and warn.)

## Smaller leftovers worth sweeping

- **`xr-driver.service` (user unit):** claims the Xreal HID interfaces via
  libusb. The old session script masked it per-login; mask it permanently:
  `systemctl --user mask xr-driver`.
- **Custodian units:** disable/remove any `kwin-vr-custodian*` units; nothing
  on the 6.6.3 line starts Monado except the plugin (via `monado.socket`
  activation — keep that socket enabled).
- **`setcap`:** the package applies `CAP_SYS_NICE` via `kwin.install` on every
  install/upgrade. If `getcap /usr/bin/kwin_wayland` is empty, reinstall or
  apply manually.
- **Pin the package:** add `IgnorePkg = kwin` to `/etc/pacman.conf` so a
  `-Syu` doesn't replace the fork with distro kwin.

## Post-migration checklist

```sh
pgrep -a kwin_wayland                     # /usr/bin/kwin_wayland
busctl --user status org.kde.kwinvr      # PID matches the above
systemctl --user show monado.service -p Environment   # DIRECT=1, no FORCE_WAYLAND=1
getcap /usr/bin/kwin_wayland             # cap_sys_nice=ep
```

Then run the `doc/SMOKE.md` lifecycle items (S1–S3).
