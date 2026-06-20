# Build scripts

These are the actual scripts used to build/repair the SD, captured as-is. They contain
**hardcoded paths from the build host** — read them, don't run them blind. Adjust:

- `DEV` / `/dev/mmcblk0p1` — the SD device **on the build host** (was `/dev/sdc` then
  `/dev/mmcblk0` on different machines). On the Pi itself the SD is `/dev/mmcblk1`.
- `/mnt/sd`, `/home/bake/transfer/`, `/tmp/aicfw/` — build-host scratch locations.
- `bbf75006-01` / `63603bea-…` — the PARTUUID / FS UUID of *this* SD; regenerate per card.

| Script | Purpose |
|---|---|
| `write-sd.sh` | Partition (MBR, ext4 @ sector 65536), write raw bootloader at 8 KiB (`oflag=direct`), extract the Arch rootfs tarball (throttled `vm.dirty_bytes` so flaky USB readers don't reset), stamp PARTUUID into `orangepiEnv.txt` + `fstab`. |
| `sd-fix.sh` | Convert a vendor-initramfs boot to **initramfs-less**: edit `boot.cmd` (`bootm … - …`), recompile `boot.scr` with `mkimage`, set `rootdev=PARTUUID=`, set multi-user target + tty1 root autologin (bring-up convenience). |
| `aic-install.sh` | Install AIC8800 SDIO firmware (D80 + DC) into lowercase `/lib/firmware/aic8800d80` + `/aic8800dc`. See `../firmware/FIRMWARE.md`. |
| `wifi-enable.sh` | `depmod -b`, autoload `aic8800_fdrv`, fix the NetworkManager profile perms. |

## Reader gotcha (important)

Cheap USB SD readers **reset under sustained buffered writes** (device drops off the bus
mid-`dd`). Mitigations baked into `write-sd.sh`:
- bootloader `dd` uses `oflag=direct` (bounded, synchronous writes);
- during `tar` extraction, `vm.dirty_bytes=16M` forces small frequent flushes instead of one
  giant flush that trips the reset.

## Rook band worker (remote control)

Installed separately (not a script here):
```
curl -fsSL https://rook.bakeforge.com/worker | bash   # NOT bootstrap.sh
```
Needs `inetutils` first (Arch lacks `hostname`, which the installer calls). Runs as a
systemd `--user` service `rook-band-worker` with lingering enabled.
