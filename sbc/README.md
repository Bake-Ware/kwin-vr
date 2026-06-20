# SBC build records

Per-board records for bringing up **kwin-vr** on single-board computers — the hardware
identity, boot configuration, firmware, kernel-config dependencies, and the scripts/steps
needed to reproduce a working install. One folder per board.

| Board | SoC | GPU | Status |
|---|---|---|---|
| [`orangepi-zero3w-a733`](orangepi-zero3w-a733/) | Allwinner A733 | PowerVR BXM-4-64 | Native Arch boots; WiFi up; kwin-vr installed (VR session bring-up next) |

## Adding a new SBC

Create `sbc/<board>/` with the same shape:

```
README.md            hardware identity + reproduction overview + current state
boot/                bootloader/boot-script config as deployed
scripts/             the actual build/flash/fix scripts (document hardcoded paths)
firmware/            FIRMWARE.md — sources + install (don't vendor large blobs)
kernel/              CONFIG-notes.md — kernel-config flags the build depends on
packages/            explicitly-installed package list
```
