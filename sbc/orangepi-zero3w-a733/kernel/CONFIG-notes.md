# BSP kernel config flags this build relies on

Kernel: Allwinner BSP **`6.6.98-sun60iw2`** (`config-6.6.98-sun60iw2` ships in `/boot`).
These are the flags that make the rest of this build work; verify them in any new BSP kernel.

## Boot without an initramfs (mount root directly)

```
CONFIG_AW_MMC=y            # Allwinner MMC host controller — BUILT IN (not the mainline
CONFIG_AW_MMC_V4P1X=y      #   CONFIG_MMC_SUNXI/CONFIG_SUNXI_MMC, which are NOT set here)
CONFIG_AW_MMC_V4P5X=y
CONFIG_AW_MMC_V5P3X=y
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_BLK_DEV_SD=y
CONFIG_EXT4_FS=y
CONFIG_DEVTMPFS=y          # NOTE: CONFIG_DEVTMPFS_MOUNT is NOT set, but systemd mounts /dev
```

If a future kernel builds `AW_MMC` or `EXT4` as a **module**, initramfs-less boot breaks and
you must regenerate a real initramfs instead.

## WiFi

```
CONFIG_AIC_WLAN_SUPPORT=y
CONFIG_AIC_INTF_SDIO=y          # SDIO interface (→ use the SDIO firmware tree)
CONFIG_AIC8800_WLAN_SUPPORT=m   # driver is a module: aic8800_fdrv (+ aic8800_bsp dep)
CONFIG_AIC8800_BTLPM_SUPPORT=m
```

## Console

`boot.cmd` sets `console=both` → `console=tty1 console=ttyS0,115200` and `earlyprintk` on
`sunxi-uart 0x02500000`. Serial debug header = `ttyS0` @ 115200.

---

The full `config-6.6.98-sun60iw2` is not committed (210 KB, ships in the image). Pull it from
`/boot/` on a running system or the vendor kernel package if you need the complete config.
