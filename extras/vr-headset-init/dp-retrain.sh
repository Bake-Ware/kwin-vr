#!/bin/bash
# Force DP connector re-detect (HPD cycle) — must run as root.
# Finds the correct DRM card for the given connector dynamically.
CONNECTOR="${1:-DP-1}"
for card_conn in /sys/class/drm/card*-"${CONNECTOR}"/status; do
    [ -f "$card_conn" ] || continue
    echo detect > "$card_conn" 2>/dev/null
    echo "HPD triggered: $card_conn"
    exit 0
done
echo "No DRM card found for connector ${CONNECTOR}"
exit 1
