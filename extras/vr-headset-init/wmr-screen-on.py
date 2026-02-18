#!/usr/bin/env python3
"""Send screen-enable command to Samsung Odyssey+ WMR headset."""
import os, glob, time

def find_hidraw(vid, pid):
    for dev in glob.glob('/sys/class/hidraw/hidraw*/device/uevent'):
        with open(dev) as f:
            content = f.read()
        if f'{vid:04X}' in content and f'{pid:04X}' in content:
            return '/dev/' + dev.split('/')[4]
    return None

# Samsung companion device (XE700X3AI) is the control interface
hidraw = find_hidraw(0x04e8, 0x7312)
if not hidraw:
    print("Samsung Odyssey control device not found")
    exit(1)

print(f"Found Odyssey control at {hidraw}")

# Send screen-on command: report ID 0x12, value 0x01
cmd = bytes([0x12, 0x01])
try:
    with open(hidraw, 'wb') as f:
        f.write(cmd)
    print("Screen-on command sent")
except PermissionError:
    print(f"Permission denied on {hidraw}")
    exit(1)

# Wait for HDMI to enumerate
print("Waiting 4s for HDMI display to come up...")
time.sleep(4)

# Check if HDMI connected
try:
    with open('/sys/class/drm/card0-HDMI-A-1/status') as f:
        status = f.read().strip()
    print(f"HDMI-A-1 status: {status}")
except:
    print("Could not read HDMI status")
