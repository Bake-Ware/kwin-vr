#!/bin/bash
# Samsung WMR headset boot init
echo 1 > /sys/bus/usb/devices/2-1.1/bConfigurationValue 2>/dev/null
chmod 666 /dev/hidraw3 /dev/hidraw4 /dev/bus/usb/002/003 2>/dev/null
sleep 1
python3 /usr/lib/vr-headset-init/wmr-screen-on.py
