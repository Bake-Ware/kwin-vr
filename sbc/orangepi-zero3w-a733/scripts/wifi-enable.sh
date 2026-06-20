#!/bin/bash
set -u
M=/mnt/sd
mountpoint -q $M || mount /dev/mmcblk0p1 $M
echo "=== regen modules.dep for BSP kernel (so modprobe resolves aic8800 deps) ==="
depmod -b $M 6.6.98-sun60iw2 2>&1 | tail -2
grep -i aic8800_fdrv $M/lib/modules/6.6.98-sun60iw2/modules.dep | head -1 && echo "depmap OK"
echo "=== autoload aic8800 at boot ==="
printf "aic8800_fdrv\n" > $M/etc/modules-load.d/aic8800.conf
cat $M/etc/modules-load.d/aic8800.conf
echo "=== WiFi profile present? ==="
ls -la $M/etc/NetworkManager/system-connections/ 2>/dev/null
for f in $M/etc/NetworkManager/system-connections/*.nmconnection; do
  echo "--- $(basename $f) ---"
  grep -E "^(ssid|autoconnect|type|key-mgmt)=" "$f" 2>/dev/null
  chmod 600 "$f"
done
echo "=== ensure NetworkManager manages wifi (no global rfkill block) ==="
ls $M/etc/systemd/system/multi-user.target.wants/ | grep -i NetworkManager && echo "NM enabled"
sync
echo "WIFI_DONE"
