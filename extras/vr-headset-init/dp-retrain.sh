#!/bin/bash
# Force DP connector re-detect (must run as root)
CONNECTOR="${1:-DP-1}"
echo detect > "/sys/class/drm/card0-${CONNECTOR}/status"
