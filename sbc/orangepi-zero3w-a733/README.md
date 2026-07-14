# Orange Pi Zero 3W (Allwinner A733) — native Arch Linux ARM build for kwin-vr

Build record for running **kwin-vr** on the Xreal/Nreal-glasses driver board. This
directory captures everything needed to reproduce a bootable native **Arch Linux ARM**
system on this SBC, on top of the Allwinner BSP kernel + closed PowerVR blobs.

> One folder per SBC. Add `sbc/<board>/` for each new board we bring up.

---

## 1. Hardware identity

| | |
|---|---|
| Marketing name | **Orange Pi Zero 3W** |
| Device-tree `model` | `sun60iw2` |
| Device-tree `compatible` | `xunlong,orangepi-4-pro`, `arm,sun60iw2p1` |
| DTB used | `allwinner/sun60i-a733-orangepi-zero3w.dtb` |
| SoC | **Allwinner A733** (`sun60iw2p1`) — 2×Cortex-A76 + 6×Cortex-A55 + RISC-V E902 + NPU |
| `sunxi_platform` | `A733` (chiptype `0x5100`, soc_ver `0x1`) |
| GPU | Imagination **PowerVR B-Series BXM-4-64** (DDK 24.2 closed blobs; **Vulkan-only** HW path) |
| RAM | ~6 GB LPDDR5 (`5.7Gi` visible) |
| Cores | 8 |
| USB | 2× USB-C: `usbc2` = USB 3.1 OTG + DP-alt (**glasses**), `usbc0` = USB 2.0 power |
| WiFi/BT | **AIC8800** (SDIO) |

The marketing name ("Zero 3W") and the DT id ("orangepi-4-pro") disagree — same A733 platform.

## 2. Kernel / userland reality

- **Kernel:** Allwinner BSP `6.6.98-sun60iw2` (`#1.0.0 SMP PREEMPT Apr 7 2026`). Mainline
  A733 has no GPU/display, so the **BSP kernel + closed blobs are mandatory** for years.
- **Userland:** Arch Linux ARM aarch64 (glibc 2.4x). PowerVR blobs built against older glibc
  run fine. GPU is **Vulkan-only** (stock Mesa can't load the 24.2 `pvr_dri.so`, so GLES =
  software — same as Debian, not a regression).
- This replaces the previous Debian-11-host + sid-nspawn-container setup. The container only
  existed because Debian 11 userland is too old for Plasma 6.

## 3. What's in this folder

```
boot/        orangepiEnv.txt + boot.cmd as deployed (initramfs-less). See boot/README.md.
scripts/     write-sd.sh, sd-fix.sh, aic-install.sh, wifi-enable.sh — the build pipeline.
firmware/    FIRMWARE.md — AIC8800 WiFi firmware source + install (binaries NOT vendored).
kernel/      CONFIG-notes.md — the BSP kernel config flags this build relies on.
packages/    pkglist-explicit.txt — explicitly-installed Arch packages on the running system.
```

## 4. Reproduce from scratch (high level)

The rootfs was built on the board itself (chroot under the running BSP kernel) — see the
project history. Once you have an Arch ARM rootfs tarball + the board's bootloader image:

1. **Partition + flash the SD** — `scripts/write-sd.sh`
   MBR, one ext4 partition starting at sector 65536, raw bootloader at 8 KiB, extract rootfs.
   ⚠️ Flaky USB SD readers reset under sustained *buffered* writes — the script uses
   `oflag=direct` for the bootloader and throttles `vm.dirty_bytes` during extraction.

2. **Make it boot (initramfs-less)** — `scripts/sd-fix.sh`
   The BSP kernel has SD/MMC + ext4 + devtmpfs built in, so no initramfs is needed. We drop
   the (Debian) initramfs entirely and let the kernel mount root directly. See `boot/README.md`.
   - `boot.cmd`: `bootm ${kernel_addr_r} - ${fdt_addr_r}` (the `-` skips the ramdisk), recompiled to `boot.scr`.
   - `orangepiEnv.txt`: `rootdev=PARTUUID=...` (a filesystem `UUID=` is **not** kernel-resolvable without an initramfs).

3. **WiFi firmware** — `scripts/aic-install.sh` + `firmware/FIRMWARE.md`
   The AIC8800 driver ships in the BSP modules but its firmware is **not** in stock
   `linux-firmware`. Install the SDIO firmware into **lowercase** `/lib/firmware/aic8800d80/`
   and `/aic8800dc/`, then `depmod -b <root> 6.6.98-sun60iw2` and autoload `aic8800_fdrv`.

4. **First boot** → text console on HDMI (`console=both` → tty1 + ttyS0,115200). Bring WiFi up,
   then it auto-connects on subsequent boots.

## 5. Current deployed state (2026-06)

- Boots initramfs-less to multi-user; `root` autologin on tty1 for bring-up (revert for prod).
- Root FS: ext4, label `ARCHROOT`, FS UUID `63603bea-…`, PARTUUID `bbf75006-01`.
- WiFi (AIC8800 D80) associates via NetworkManager profile `Agamemnon`, autoconnect on,
  powersave off.
- kwin-vr (`kwin_wayland` + `vr.so`) installed to `/usr`; PowerVR Vulkan enumerates the
  BXM-4-64. Graphical/VR session bring-up on the glasses is the next milestone.

## 6. Gotchas worth remembering

- **Arch has no `hostname` binary** — install `inetutils`. Its absence breaks naive
  `ssh host hostname` probes (use `uname -n`) and the rook worker installer.
- **Root SSH** is blocked by Arch default (`PermitRootLogin prohibit-password`); use a normal
  user. Setting `PasswordAuthentication yes` alone is not enough.
- **`UUID=` vs `PARTUUID=`**: only `PARTUUID=`/`/dev/...` are kernel-resolvable without an
  initramfs.
- The board's SD is `/dev/mmcblk1` on the Pi (not `mmcblk0`).
