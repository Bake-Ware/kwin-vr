#!/usr/bin/env python3
"""Switch Xreal Air glasses to SBS (3D) display mode via HID control interface.

Sends a W_DISP_MODE command (msgid 0x0008) with mode=0x03 (3D/SBS) to the
control interface (USB interface 4) of the Xreal Air Gen 1 glasses.

Protocol reference: Monado xreal_air_hmd.c send_payload_to_control()
"""
import glob
import os
import struct
import sys
import binascii

VID = 0x3318
PID = 0x0424
CONTROL_IFACE = 4
PACKET_SIZE = 64
HEADER = 0xFD
MSGID_W_DISP_MODE = 0x0008
MODE_3D_SBS = 0x03


def find_control_hidraw():
    """Find the hidraw device for the Xreal Air control interface (iface 4)."""
    for uevent_path in glob.glob('/sys/class/hidraw/hidraw*/device/uevent'):
        with open(uevent_path) as f:
            content = f.read()
        if f'{VID:04X}' not in content or f'{PID:04X}' not in content:
            continue

        # Check that this is interface 4 (control), not interface 3 (sensor)
        # The device path contains `:1.4` for interface 4
        hidraw_name = uevent_path.split('/')[4]  # e.g. "hidraw2"
        device_link = f'/sys/class/hidraw/{hidraw_name}/device'
        real_path = os.path.realpath(device_link)

        if f':{CONTROL_IFACE:d}' not in real_path and f'.{CONTROL_IFACE:d}/' not in real_path:
            print(f"Skipping {hidraw_name}: not control interface (path: {real_path})")
            continue

        return f'/dev/{hidraw_name}'
    return None


def build_sbs_packet():
    """Build the 64-byte control packet to set display mode to 3D/SBS."""
    packet = bytearray(PACKET_SIZE)

    # Header
    packet[0] = HEADER

    # Bytes 5-6: packet_len = 17 + data_len (data_len=1 for display mode)
    packet_len = 17 + 1  # 18
    struct.pack_into('<H', packet, 5, packet_len)

    # Bytes 7-14: timestamp (8 zero bytes - already zero)

    # Bytes 15-16: msgid (little-endian)
    struct.pack_into('<H', packet, 15, MSGID_W_DISP_MODE)

    # Bytes 17-21: reserved (5 zero bytes - already zero)

    # Byte 22: display_mode = 0x03 (3D/SBS)
    packet[22] = MODE_3D_SBS

    # Bytes 1-4: CRC32 over bytes [5..5+packet_len-1] = bytes [5..22]
    crc_data = bytes(packet[5:5 + packet_len])
    crc = binascii.crc32(crc_data) & 0xFFFFFFFF
    struct.pack_into('<I', packet, 1, crc)

    return bytes(packet)


def main():
    hidraw = find_control_hidraw()
    if not hidraw:
        print(f"Xreal Air control interface not found (VID {VID:04x}:PID {PID:04x} iface {CONTROL_IFACE})")
        sys.exit(1)

    print(f"Found Xreal Air control at {hidraw}")

    packet = build_sbs_packet()
    print(f"Sending SBS mode command ({len(packet)} bytes)...")

    try:
        fd = open(hidraw, 'r+b', buffering=0)
    except PermissionError:
        print(f"Permission denied on {hidraw}")
        sys.exit(1)

    try:
        fd.write(packet)
        print("Command sent, reading response...")

        response = fd.read(PACKET_SIZE)
        if response and len(response) >= 23:
            status = response[22]
            if status == 0x00:
                print("SBS mode switch confirmed (status=0x00)")
            else:
                print(f"SBS mode switch returned status=0x{status:02x}")
        else:
            print(f"Short/no response ({len(response) if response else 0} bytes)")
    finally:
        fd.close()


if __name__ == '__main__':
    main()
