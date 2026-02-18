#!/bin/bash
# Detect VR hardware and run headset-specific init
# Retry up to 10 times (5 seconds) to handle USB enumeration race

PROFILE=""
for i in $(seq 1 10); do
    PROFILE=$(/usr/lib/vr-headset-init/vr-detect.sh 2>/dev/null)
    [ $? -eq 0 ] && break
    PROFILE=""
    sleep 0.5
done

if [ -z "$PROFILE" ]; then
    echo "No VR headset detected after 5s"
    echo "none" > /run/vr-detected
    exit 0
fi

source "$PROFILE"
echo "$PROFILE" > /run/vr-detected
chmod 644 /run/vr-detected

echo "Detected: $VR_NAME"

# Run headset-specific init if defined
if [ -n "$VR_BOOT_INIT" ] && [ -x "$VR_BOOT_INIT" ]; then
    echo "Running init: $VR_BOOT_INIT"
    "$VR_BOOT_INIT"
fi
