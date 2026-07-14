#!/bin/bash
set -u
M=/mnt/sd
SDIO=/tmp/aicfw/aic8800/src/SDIO/driver_fw/fw
mountpoint -q $M || mount /dev/mmcblk0p1 $M
echo "=== source dirs ==="
ls $SDIO
echo "=== D80 dir contents ==="; ls $SDIO/aic8800D80 2>/dev/null | head
echo "=== DC dir contents ==="; ls $SDIO/aic8800DC 2>/dev/null | head
echo "=== base aic8800 dir contents ==="; ls $SDIO/aic8800 2>/dev/null | head

echo "=== install to lowercase /lib/firmware dirs ==="
mkdir -p $M/lib/firmware/aic8800d80 $M/lib/firmware/aic8800dc $M/lib/firmware/aic8800
cp -av $SDIO/aic8800D80/. $M/lib/firmware/aic8800d80/ >/dev/null 2>&1 && echo "d80 copied: $(ls $M/lib/firmware/aic8800d80 | wc -l) files"
cp -av $SDIO/aic8800DC/.  $M/lib/firmware/aic8800dc/  >/dev/null 2>&1 && echo "dc copied: $(ls $M/lib/firmware/aic8800dc | wc -l) files"
cp -av $SDIO/aic8800/.    $M/lib/firmware/aic8800/    >/dev/null 2>&1 && echo "base copied: $(ls $M/lib/firmware/aic8800 | wc -l) files"
# fdrv requests these base names directly from /lib/firmware/ root
for f in fmacfw.bin fmacfw.ihex ldpcram.bin fcuram.bin agcram.bin rwnx_settings.ini; do
  src=$(find $SDIO/aic8800 -name "$f" 2>/dev/null | head -1)
  [ -n "$src" ] && cp -a "$src" $M/lib/firmware/ && echo "root: $f"
done
echo "=== verify the D80 files the bsp module names (u02 set) ==="
for f in fmacfw_8800d80_u02.bin fw_patch_8800d80_u02.bin fw_patch_table_8800d80_u02.bin fw_adid_8800d80_u02.bin lmacfw_rf_8800d80_u02.bin aic_userconfig_8800d80.txt; do
  [ -f $M/lib/firmware/aic8800d80/$f ] && echo "OK  $f" || echo "MISS $f"
done
echo "=== verify DC files ==="
for f in fmacfw_patch_8800dc_u02.bin fmacfw_patch_tbl_8800dc_u02.bin fmacfw_rf_8800dc.bin fw_adid_8800dc_u02.bin aic_userconfig_8800dc.txt; do
  [ -f $M/lib/firmware/aic8800dc/$f ] && echo "OK  $f" || echo "MISS $f"
done
sync
echo "INSTALL_DONE"
