#!/usr/bin/env python3
"""
capture_hid_init.py — Capture the MPK mini IV HID activation packet

Run AFTER: sudo modprobe usbmon
           sudo chmod a+r /dev/usbmon1

This reads raw USB traffic from usbmon, filters for the MPK mini IV
(VID:09e8 PID:005d, Bus 1 Dev 6), and prints every HOST→DEVICE
HID output report that any program sends to it.

Launch the Akai Firmware Updater (or Editor) in Wine WHILE this is
running to capture the initialization sequence.

Usage:
    python3 capture_hid_init.py [--bus 1] [--dev 6] [--out capture.txt]

Outputs:
    - Console: decoded packets as they arrive
    - capture.txt: machine-readable hex dump for replay_hid_init.py
"""

import struct, sys, time, argparse, signal
from pathlib import Path
from datetime import datetime

# ── usbmon binary packet format (linux/usb/mon.h) ─────────────────────────────
# struct usbmon_packet { u64 id; u8 type; u8 xfer_type; u8 epnum; u8 devnum;
#                        u16 busnum; char flag_setup; char flag_data;
#                        s64 ts_sec; s32 ts_usec; int status;
#                        u32 length; u32 len_cap; u8 setup[8];
#                        int interval; int start_frame;
#                        u32 xfer_flags; u32 ndesc; }  — 64 bytes
# Correct layout (verified against linux/usb/mon.h):
#   Q(id) BBBBHcc(type,xfer,ep,dev,bus,flags) q(ts_sec) i(ts_usec)
#   i(status) II(length,len_cap) 8s(setup union) ii(interval,start)
#   II(xfer_flags,ndesc) = 8+4+2+2+8+4+4+4+8+4+4+4+4 = 64
HDR_FMT  = "<QBBBBHccqiiII8siiII"
HDR_SIZE = struct.calcsize(HDR_FMT)
if HDR_SIZE != 64:
    raise RuntimeError(f"struct size={HDR_SIZE}, expected 64 — check python struct module")

XFER_CTRL = 0; XFER_ISO = 1; XFER_BULK = 2; XFER_INTR = 3
XFER_NAMES = {0:"CTRL",1:"ISO",2:"BULK",3:"INTR"}

# Fields from unpack (HDR_FMT "<QBBBBHccqiiII8siiII"):
# [0]=id  [1]=type  [2]=xfer_type  [3]=epnum  [4]=devnum  [5]=busnum
# [6]=flag_setup(bytes)  [7]=flag_data(bytes)
# [8]=ts_sec  [9]=ts_usec  [10]=status  [11]=length  [12]=len_cap
# [13]=setup[8](bytes union)  [14]=interval  [15]=start_frame
# [16]=xfer_flags  [17]=ndesc


def fmt_bytes(b: bytes, group=8) -> str:
    hex_part = ' '.join(f'{x:02X}' for x in b)
    asc_part = ''.join(chr(x) if 32 <= x < 127 else '.' for x in b)
    return f"{hex_part:<{group*3}}  {asc_part}"


def parse_stream(fp, target_dev: int, log_fp=None, verbose=False):
    """Read usbmon binary stream and yield (ts, direction, ep, xfer_type, data)
    for packets to/from target_dev."""
    buf = b""
    captures = []

    print(f"\n[capture] Watching Bus for device address {target_dev} ...")
    print("[capture] Waiting for host→device HID output reports (type='S', ep bit7=0)\n")

    while True:
        chunk = fp.read(4096)
        if not chunk:
            break
        buf += chunk

        while len(buf) >= HDR_SIZE:
            fields = struct.unpack_from(HDR_FMT, buf, 0)
            urb_id, typ, xfer_type, epnum, devnum, busnum = fields[:6]
            flag_setup, flag_data = fields[6], fields[7]
            ts_sec, ts_usec, status, length, len_cap = fields[8:13]

            # HDR_SIZE=64, then len_cap bytes of data follow
            total = HDR_SIZE + len_cap
            if len(buf) < total:
                break  # wait for more data

            data = buf[HDR_SIZE:total]
            buf = buf[total:]

            # Filter: only our target device
            if devnum != target_dev:
                continue

            direction_in = bool(epnum & 0x80)  # bit 7 = IN (device→host)
            ep_num = epnum & 0x7F

            ts = ts_sec + ts_usec / 1_000_000
            ts_str = datetime.fromtimestamp(ts).strftime("%H:%M:%S.%f")[:-3]

            # 'S' = SUBMIT (host→device), 'C' = COMPLETE (device→host response)
            pkt_type = chr(typ)

            if verbose:
                dir_str = "←IN " if direction_in else "→OUT"
                print(f"  [{ts_str}] {pkt_type} {XFER_NAMES.get(xfer_type,'?')} ep{ep_num:02d} "
                      f"{dir_str} len={len_cap} status={status}")
                if data:
                    print(f"    {fmt_bytes(data[:32])}")

            # We want: SUBMIT (host→device) on interrupt endpoint, no direction bit
            # These are the HID output reports the host sends to the device
            if pkt_type == 'S':
                if not direction_in and xfer_type == XFER_INTR and len_cap > 0:
                    print(f"\n{'═'*60}")
                    print(f"  *** HOST→DEVICE HID OUTPUT REPORT ***")
                    print(f"  Time:  {ts_str}")
                    print(f"  EP:    {ep_num}  Bytes: {len_cap}")
                    print(f"  Hex:   {' '.join(f'{b:02X}' for b in data)}")
                    print(f"{'═'*60}\n")
                    captures.append((ts, data))
                    if log_fp:
                        log_fp.write(f"# {ts_str}  ep={ep_num}  len={len_cap}\n")
                        log_fp.write(' '.join(f'{b:02X}' for b in data) + '\n\n')
                        log_fp.flush()

            # Also show CONTROL transfers (SETUP phase) host→device
            # flag_setup == b'=' means the 8-byte setup packet is valid
            if pkt_type == 'S' and xfer_type == XFER_CTRL and flag_setup in (b'=', 61) and len_cap >= 8:
                setup = data[:8] if len(data) >= 8 else fields[13]  # fall back to setup union
                bm_req  = setup[0]; b_req = setup[1]
                w_val   = struct.unpack_from('<H', setup, 2)[0]
                w_index = struct.unpack_from('<H', setup, 4)[0]
                w_len   = struct.unpack_from('<H', setup, 6)[0]
                # HID SET_REPORT = bmRequest=0x21, bRequest=0x09
                if bm_req == 0x21 and b_req == 0x09:
                    rtype = (w_val >> 8) & 0x03  # 1=Input,2=Output,3=Feature
                    rtype_names = {1:"INPUT",2:"OUTPUT",3:"FEATURE"}
                    print(f"\n{'═'*60}")
                    print(f"  *** HID SET_REPORT (CONTROL) ***")
                    print(f"  Time:   {ts_str}")
                    print(f"  Type:   {rtype_names.get(rtype,'?')}  ID: {w_val & 0xFF}")
                    print(f"  Length: {w_len}")
                    print(f"{'═'*60}\n")

    return captures


def main():
    ap = argparse.ArgumentParser(description="Capture MPK mini IV HID init packet via usbmon")
    ap.add_argument("--bus", type=int, default=1, help="USB bus number (default: 1)")
    ap.add_argument("--dev", type=int, default=0,
                    help="USB device address (0 = auto-detect, default)")
    ap.add_argument("--out", default="hid_captures.txt",
                    help="Output file for captured packets (default: hid_captures.txt)")
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="Show ALL packets, not just HID outputs")
    args = ap.parse_args()

    # Auto-detect device address from lsusb
    dev_addr = args.dev
    if dev_addr == 0:
        import subprocess
        try:
            out = subprocess.check_output(["lsusb", "-d", "09e8:005d"], text=True)
            # "Bus 001 Device 006: ID 09e8:005d ..."
            import re
            m = re.search(r"Bus (\d+) Device (\d+)", out)
            if m:
                bus = int(m.group(1)); dev_addr = int(m.group(2))
                if bus != args.bus:
                    print(f"Note: device found on bus {bus}, overriding --bus")
                    args.bus = bus
                print(f"Auto-detected: Bus {args.bus} Device {dev_addr}")
        except Exception as e:
            print(f"Could not auto-detect device address: {e}")
            print("Use: lsusb -d 09e8:005d  to find Bus and Device numbers")
            print("Then run: python3 capture_hid_init.py --bus N --dev M")
            sys.exit(1)

    usbmon_path = f"/dev/usbmon{args.bus}"
    if not Path(usbmon_path).exists():
        print(f"ERROR: {usbmon_path} not found.")
        print()
        print("Run these commands first (requires sudo):")
        print("  sudo modprobe usbmon")
        print(f"  sudo chmod a+r {usbmon_path}")
        print()
        print("Or run this script with sudo.")
        sys.exit(1)

    print(f"Opening {usbmon_path}  (device {dev_addr})")
    print(f"Captures will be saved to: {args.out}")
    print()
    print("NOW: launch the Akai MPK mini IV software in Wine or on Windows.")
    print("     The moment it connects to the device you'll see the packet here.")
    print("     Press Ctrl+C when done.")
    print()

    captures = []
    try:
        with open(usbmon_path, "rb") as fp, open(args.out, "w") as log_fp:
            log_fp.write(f"# MPK mini IV HID Init Capture — {datetime.now()}\n")
            log_fp.write(f"# Bus {args.bus} Device {dev_addr}\n\n")
            captures = parse_stream(fp, dev_addr, log_fp, verbose=args.verbose)
    except PermissionError:
        print(f"Permission denied on {usbmon_path}.")
        print(f"Run: sudo chmod a+r {usbmon_path}  or run this script with sudo.")
        sys.exit(1)
    except KeyboardInterrupt:
        pass

    print(f"\n\nCapture complete. {len(captures)} HID output report(s) found.")
    if captures:
        print(f"Saved to: {args.out}")
        print("\nFirst captured packet:")
        ts, data = captures[0]
        print(f"  {' '.join(f'{b:02X}' for b in data)}")
        print(f"\nTo replay this packet, run:")
        print(f"  python3 replay_hid_init.py {args.out}")
    else:
        print("No HID output reports captured.")
        print("Make sure you launched the Akai software WHILE this script was running.")


if __name__ == "__main__":
    main()
