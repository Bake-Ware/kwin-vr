#!/bin/bash
# Xreal Air boot init: set permissions and start mode watcher.
# The glasses boot in 2D mode (1920x1080) showing the desktop.
# When the user presses the SBS button on the glasses, the mode
# changes to 3840x1080 and the mode-watcher auto-activates VR.
chmod 666 /dev/hidraw* 2>/dev/null
