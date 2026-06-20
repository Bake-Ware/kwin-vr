# Firmware

## AIC8800 WiFi/BT (SDIO) — REQUIRED, not in stock linux-firmware

The board's WiFi/BT is an **AIC8800** on SDIO. The kernel driver ships in the BSP modules:

```
/lib/modules/6.6.98-sun60iw2/kernel/bsp/drivers/net/wireless/aic8800/
  aic8800_fdrv/aic8800_fdrv.ko    (depends on aic8800_bsp)
  aic8800_bsp/aic8800_bsp.ko
  aic8800_btlpm/aic8800_btlpm.ko
```

…but the **firmware blobs are not** in Arch's `linux-firmware`, so `wlan0` never appears
until you add them. Module version on this build: `20250410-011-6.4.3.0`.

### Source

`https://github.com/radxa-pkg/aic8800` → `src/SDIO/driver_fw/fw/`
(use the **SDIO** tree, not USB/PCIE). Variant dirs there: `aic8800D80`, `aic8800DC`,
`aic8800D80N`, `aic8800D80X2`.

### Install (see `../scripts/aic-install.sh`)

The bsp module requests **lowercase** paths (`aic8800d80/…`, `aic8800dc/…`) and the chip is
auto-detected by SDIO id, so install **both** D80 and DC variants — only the matching one is
used. This board is the **D80** variant (the D80 `_u02` set is what loads).

```
mkdir -p /lib/firmware/aic8800d80 /lib/firmware/aic8800dc
cp -a <repo>/src/SDIO/driver_fw/fw/aic8800D80/. /lib/firmware/aic8800d80/
cp -a <repo>/src/SDIO/driver_fw/fw/aic8800DC/.  /lib/firmware/aic8800dc/
# regenerate dep map for the BSP kernel, then autoload
depmod -b <rootfs-mountpoint-or-/> 6.6.98-sun60iw2
echo aic8800_fdrv > /etc/modules-load.d/aic8800.conf
```

The exact files present on the working system are listed in `aic8800-files.txt` (for matching
against a future firmware drop).

> Binaries are intentionally **not vendored** here. If upstream disappears, mirror that repo.

## PowerVR GPU (DDK 24.2, Vulkan)

Closed Imagination blobs, built only for the BSP kernel. Not WiFi-related; covered in the
project's PowerVR notes (libVK_IMG + `/etc/vulkan/icd.d/img_bxm_icd.json`, plus
`libsrv_um`/`libusc`/`libufwriter` which the usual `*PVR*` glob misses).
