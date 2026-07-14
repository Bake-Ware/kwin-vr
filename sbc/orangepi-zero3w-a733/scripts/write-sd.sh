#!/bin/bash
# Flash the Arch rootfs + Allwinner bootloader onto the small SD (/dev/sdc) on cachyrig.
set -euo pipefail
DEV=/dev/sdc
TAR=/home/bake/transfer/rootfs.tar.gz
BL=/home/bake/transfer/bootloader.img
MNT=/mnt/archsd

[ -b "$DEV" ] || { echo "FATAL: $DEV not a block device"; exit 1; }
[ -f "$TAR" ] || { echo "FATAL: $TAR missing"; exit 1; }
[ -f "$BL" ]  || { echo "FATAL: $BL missing"; exit 1; }

echo "=== TARGET (must be the 58G SD, NOT a system disk) ==="
lsblk -dno NAME,SIZE,MODEL "$DEV"

echo "=== unmount anything on $DEV ==="
for p in ${DEV}*; do umount "$p" 2>/dev/null || true; done

echo "=== wipe + new MBR, one ext4 partition from sector 65536 (32MiB) to end ==="
wipefs -a "$DEV"
parted -s "$DEV" mklabel msdos
parted -s "$DEV" unit s mkpart primary ext4 65536 100%
partprobe "$DEV"; sleep 1
PART=${DEV}1
[ -b "$PART" ] || { echo "FATAL: $PART did not appear"; exit 1; }

echo "=== write Allwinner SPL/U-Boot at 8KiB (direct IO; does NOT touch MBR @ sector0) ==="
# bootloader.img begins at byte 8192 (=8KiB=1*8k block). direct IO keeps the flaky reader from a big buffered flush.
dd if="$BL" of="$DEV" bs=8k seek=1 conv=notrunc oflag=direct status=none
sync
echo "bootloader written"

echo "=== mkfs.ext4 on $PART ==="
mkfs.ext4 -F -L ARCHROOT "$PART"
UUID=$(blkid -s UUID -o value "$PART")
echo "new rootfs UUID=$UUID"

echo "=== extract rootfs (throttled dirty cache to spare the flaky reader) ==="
mkdir -p "$MNT"
mount "$PART" "$MNT"
# small dirty thresholds => kernel flushes in frequent small bursts, never one giant flush that resets the reader
OLD_DB=$(cat /proc/sys/vm/dirty_bytes); OLD_BG=$(cat /proc/sys/vm/dirty_background_bytes)
echo $((16*1024*1024)) > /proc/sys/vm/dirty_bytes
echo $((8*1024*1024))  > /proc/sys/vm/dirty_background_bytes
tar -I 'gzip' -xpf "$TAR" -C "$MNT" --numeric-owner
sync
# restore
echo "$OLD_DB" > /proc/sys/vm/dirty_bytes 2>/dev/null || echo 0 > /proc/sys/vm/dirty_bytes
echo "$OLD_BG" > /proc/sys/vm/dirty_background_bytes 2>/dev/null || true

echo "=== set rootdev in orangepiEnv.txt + fstab ==="
sed -i -E "s|^rootdev=.*|rootdev=UUID=$UUID|" "$MNT/boot/orangepiEnv.txt"
grep -q "^rootdev=UUID=$UUID" "$MNT/boot/orangepiEnv.txt" && echo "orangepiEnv ok" || { echo "FATAL: orangepiEnv sed failed"; cat "$MNT/boot/orangepiEnv.txt"; exit 1; }
sed -i -E "s|^(PARTUUID=ARCHROOT_PLACEHOLDER\|UUID=[^ ]+)(\s+/\s.*)|UUID=$UUID\2|" "$MNT/etc/fstab"
echo "--- fstab ---"; grep -vE '^\s*#' "$MNT/etc/fstab"
echo "--- orangepiEnv.txt ---"; cat "$MNT/boot/orangepiEnv.txt"

echo "=== verify key bits present ==="
ls "$MNT/boot/uImage" "$MNT/boot/uInitrd" "$MNT/boot/boot.scr" >/dev/null && echo "boot files: OK"
ls "$MNT/usr/local/bin/geppetto-uhid" >/dev/null && echo "geppetto: OK"
ls "$MNT/lib/modules/6.6.98-sun60iw2/kernel" >/dev/null 2>&1 && echo "modules: OK" || echo "modules: MISSING"

echo "=== unmount + sync ==="
umount "$MNT"
sync
echo "SD_DONE"
