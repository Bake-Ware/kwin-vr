#!/bin/bash
set -u
M=/mnt/sd
B=$M/boot
ts=backup
echo "=== backup ==="
cp -n $B/orangepiEnv.txt $B/orangepiEnv.txt.$ts
cp -n $B/boot.cmd $B/boot.cmd.$ts
cp -n $B/boot.scr $B/boot.scr.$ts
echo "backed up"

echo "=== 1) boot.cmd: skip initramfs (bootm kernel - fdt), comment uInitrd load ==="
sed -i 's|^bootm .*|bootm ${kernel_addr_r} - ${fdt_addr_r}|' $B/boot.cmd
sed -i '/uInitrd/ s|^load|#load|' $B/boot.cmd
echo "--- bootm + uInitrd lines now ---"
grep -nE "bootm |uInitrd" $B/boot.cmd

echo "=== 2) recompile boot.scr ==="
mkimage -C none -A arm -T script -d $B/boot.cmd $B/boot.scr | tail -3

echo "=== 3) orangepiEnv.txt: rootdev -> PARTUUID (kernel-resolvable, no initramfs) ==="
sed -i 's|^rootdev=.*|rootdev=PARTUUID=bbf75006-01|' $B/orangepiEnv.txt
cat $B/orangepiEnv.txt

echo "=== 4) boot to TEXT console (disable graphical/sddm for now) ==="
ln -sf /usr/lib/systemd/system/multi-user.target $M/etc/systemd/system/default.target
echo "default.target -> $(readlink $M/etc/systemd/system/default.target)"

echo "=== 5) root autologin on tty1 (HDMI) ==="
mkdir -p $M/etc/systemd/system/getty@tty1.service.d
cat > $M/etc/systemd/system/getty@tty1.service.d/autologin.conf <<'CONF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I $TERM
CONF
cat $M/etc/systemd/system/getty@tty1.service.d/autologin.conf

echo "=== 6) sanity: kernel+dtb present, root partuuid matches ==="
ls -la $B/uImage $B/dtb/allwinner/sun60i-a733-orangepi-zero3w.dtb >/dev/null && echo "kernel+dtb OK"
blkid -s PARTUUID -o value /dev/mmcblk0p1

echo "=== 7) flush + unmount ==="
sync
umount $M && echo "unmounted clean" || echo "UMOUNT FAILED (in use?)"
echo "FIX_DONE"
