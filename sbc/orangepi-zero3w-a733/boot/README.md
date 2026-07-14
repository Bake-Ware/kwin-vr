# Boot configuration (initramfs-less)

U-Boot on this board reads `boot.scr` (compiled from `boot.cmd`), which imports
`orangepiEnv.txt` and then `bootm`'s the kernel.

## The key change: no initramfs

The vendor image boots `uImage` **+** `uInitrd` (a Debian initramfs). Booting the Arch
rootfs that way hangs in the Debian initramfs at `/scripts/init-premount`
(`Starting version 247.3-7+deb11u7` is the tell — that's Debian systemd, not Arch).

The BSP kernel has everything needed to mount root built in:
`CONFIG_AW_MMC=y`, `CONFIG_MMC_BLOCK=y`, `CONFIG_EXT4_FS=y`, `CONFIG_BLK_DEV_SD=y`,
`CONFIG_DEVTMPFS=y`. So we drop the initramfs entirely:

1. In `boot.cmd`, the boot call is:
   ```
   bootm ${kernel_addr_r} - ${fdt_addr_r}
   ```
   The `-` in the ramdisk slot means "no initramfs". The `load ... uInitrd` line is commented.

2. Recompile `boot.scr`:
   ```
   mkimage -C none -A arm -T script -d boot.cmd boot.scr
   ```
   (`mkimage` is in the `uboot-tools` / `u-boot-tools` package.)

3. In `orangepiEnv.txt`, root is given by **PARTUUID**:
   ```
   rootdev=PARTUUID=bbf75006-01
   ```
   A filesystem `UUID=` is NOT resolvable by the kernel without an initramfs — only
   `PARTUUID=`, `PARTLABEL=` (GPT only), or `/dev/...` work. `rootwait` (set in `boot.cmd`)
   covers the SD taking a moment to enumerate.

`console=both` in `boot.cmd` gives a console on **tty1 (HDMI)** and **ttyS0,115200 (serial)**.

## Bootloader (raw sectors)

The Allwinner SPL/U-Boot lives in raw SD sectors (8 KiB … ~32 MiB), before the first
partition (which starts at sector 65536). `scripts/write-sd.sh` writes it with
`dd ... seek=8k oflag=direct`. It does **not** touch the MBR at sector 0.

## Files here

- `orangepiEnv.txt` — as deployed (PARTUUID root). Replace the PARTUUID for a new SD.
- `boot.cmd` — as deployed (initramfs-less). Recompile to `boot.scr` after any edit.
