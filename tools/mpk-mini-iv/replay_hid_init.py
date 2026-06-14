#!/usr/bin/env python3
"""
replay_hid_init.py — Send the captured HID activation packet to the MPK mini IV

After running capture_hid_init.py and getting the activation bytes,
this script replays them to unlock the OLED encoder / button HID reports.

Usage:
    python3 replay_hid_init.py                    # replay from hid_captures.txt
    python3 replay_hid_init.py capture.txt        # replay from specific file
    python3 replay_hid_init.py --probe            # try known patterns systematically
    python3 replay_hid_init.py --listen           # just listen for HID input (no send)
"""

import sys, time, argparse, threading
from pathlib import Path

try:
    import hid
except ImportError:
    sys.exit("Error: python-hid not installed.\n  sudo pacman -S python-hid")

VID = 0x09E8
PID = 0x005D
READ_TIMEOUT_MS = 500
REPORT_LEN = 32


def open_device() -> hid.Device:
    try:
        d = hid.Device(VID, PID)
        print(f"Opened: {d.manufacturer} {d.product}  (serial: {d.serial})")
        return d
    except Exception as e:
        sys.exit(f"Could not open MPK mini IV HID device: {e}\n"
                 f"Make sure it's plugged in and you're in the 'audio' group.")


def listen_loop(dev: hid.Device, stop_event: threading.Event, verbose=True):
    """Read HID input reports from device, print any non-zero data."""
    dev.nonblocking = False
    print("[listen] Waiting for HID input from device (encoder / buttons)...")
    while not stop_event.is_set():
        try:
            data = dev.read(REPORT_LEN, timeout=READ_TIMEOUT_MS)
            if data and any(b != 0 for b in data):
                print(f"  ← DEVICE INPUT: {' '.join(f'{b:02X}' for b in data)}")
        except Exception as e:
            if not stop_event.is_set():
                print(f"[listen] read error: {e}")
            break


def send_report(dev: hid.Device, payload: bytes, label: str = ""):
    """Send a 32-byte HID output report (hidapi prepends report ID 0x00)."""
    # hidapi requires the first byte to be the report ID (0x00 when none defined)
    msg = bytes([0x00]) + payload[:REPORT_LEN].ljust(REPORT_LEN, b'\x00')
    n = dev.write(msg)
    tag = f"  [{label}]" if label else ""
    print(f"  → SENT ({n} bytes written){tag}: {' '.join(f'{b:02X}' for b in payload[:REPORT_LEN])}")


def replay_from_file(path: str):
    packets = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        try:
            b = bytes(int(x, 16) for x in line.split())
            if len(b) > 0:
                packets.append(b)
        except ValueError:
            continue

    if not packets:
        sys.exit(f"No packets found in {path}")

    print(f"Loaded {len(packets)} packet(s) from {path}\n")

    dev = open_device()
    stop = threading.Event()
    t = threading.Thread(target=listen_loop, args=(dev, stop), daemon=True)
    t.start()

    for i, pkt in enumerate(packets):
        print(f"\nSending packet {i+1}/{len(packets)}:")
        send_report(dev, pkt, f"pkt{i+1}")
        time.sleep(0.5)

    print("\nWaiting 3s for device response...")
    time.sleep(3)
    stop.set()
    dev.close()


def probe_known_patterns():
    """
    Systematically try known HID activation patterns from inMusic/Akai devices.
    Patterns from community research and related device reverse engineering.
    After each send, watch for any non-zero HID input for 1 second.
    """
    dev = open_device()
    stop = threading.Event()
    t = threading.Thread(target=listen_loop, args=(dev, stop), daemon=True)
    t.start()

    # Patterns to try — each is a 32-byte output report
    # Notation: hex bytes, padded to 32 with 0x00
    patterns = [
        # ── Observed from related inMusic devices ────────────────────────────
        # AKAI VPD / MPC-style vendor init
        ("AKAI-01",    "47 7F 01 00"),
        ("AKAI-02",    "47 7F 04 00"),
        ("AKAI-03",    "06 47 7F 01"),
        ("AKAI-PING",  "06 00 00 00"),
        # ── MPC mini / MPK mini II patterns (may share protocol) ─────────────
        ("MPK-INIT1",  "49 4E 49 54"),  # "INIT" ASCII
        ("MPK-INIT2",  "01 47 00 5D"),  # cmd + Akai VID bytes
        # ── Generic vendor HID activate patterns ─────────────────────────────
        ("VND-01",     "01 00 00 00"),
        ("VND-02",     "02 00 00 00"),
        ("VND-03",     "03 00 00 00"),
        ("VND-0F",     "0F 00 00 00"),
        ("VND-10",     "10 00 00 00"),
        ("VND-11",     "11 00 00 00"),
        ("VND-12",     "12 00 00 00"),
        ("VND-20",     "20 00 00 00"),
        ("VND-40",     "40 00 00 00"),
        ("VND-41",     "41 00 00 00"),  # 'A'
        ("VND-4E",     "4E 00 00 00"),  # 'N'
        ("VND-FF",     "FF 00 00 00"),
        # ── Akai specific from firmware strings ──────────────────────────────
        ("AK-FWMODE",  "F0 00 00 00"),   # firmware/DFU mode
        ("AK-EDMODE",  "E0 00 00 00"),   # editor mode?
        ("AK-HOST1",   "48 4F 53 54"),   # "HOST" ASCII
        ("AK-HOST2",   "68 6F 73 74"),   # "host" lowercase
        # ── From MPK mini IV HID descriptor: usage 0x03/0x04 ────────────────
        # Usage page 0xFF A1, usages 0x03 and 0x04 are the output/input items
        ("DESC-U03",   "03 00 00 00"),
        ("DESC-U04",   "04 00 00 00"),
        ("DESC-U0304", "03 04 00 00"),
        # ── Try with logical min/max from descriptor (0x18=24, 0x7F=127) ────
        ("LOGIC-MIN",  "18 18 18 18 18 18 18 18"),
        ("LOGIC-MX",   "7F 7F 7F 7F 7F 7F 7F 7F"),
    ]

    print(f"\nProbing {len(patterns)} patterns. Watch for '← DEVICE INPUT' lines.\n")

    for label, hex_str in patterns:
        raw = bytes(int(x, 16) for x in hex_str.split())
        payload = raw.ljust(REPORT_LEN, b'\x00')
        print(f"\n[{label:12s}] Sending: {' '.join(f'{b:02X}' for b in payload[:8])} ...")
        try:
            send_report(dev, payload, label)
        except Exception as e:
            print(f"  Write error: {e}")
            continue
        time.sleep(0.8)  # wait for response

    print("\n\nProbe complete. Waiting 2s for any remaining responses...")
    time.sleep(2)
    stop.set()
    dev.close()

    print("\nIf no '← DEVICE INPUT' lines appeared, try running capture_hid_init.py")
    print("while the Akai Firmware Updater is running in Wine.")


def just_listen(seconds: int = 30):
    """Open HID and listen for input reports. No writing."""
    dev = open_device()
    dev.nonblocking = False
    print(f"\nListening for {seconds}s — interact with the device encoder/buttons now...")
    deadline = time.time() + seconds
    found = []
    while time.time() < deadline:
        try:
            data = dev.read(REPORT_LEN, timeout=READ_TIMEOUT_MS)
            if data and any(b != 0 for b in data):
                print(f"  ← INPUT: {' '.join(f'{b:02X}' for b in data)}")
                found.append(bytes(data))
        except Exception:
            break
    dev.close()
    if found:
        print(f"\n{len(found)} input report(s) received — device IS in host mode!")
    else:
        print("\nNo input data received — device needs activation packet first.")


def main():
    ap = argparse.ArgumentParser(description="Replay HID activation packet to MPK mini IV")
    ap.add_argument("capture_file", nargs="?", default="hid_captures.txt",
                    help="File from capture_hid_init.py (default: hid_captures.txt)")
    ap.add_argument("--probe",  action="store_true",
                    help="Try known activation patterns systematically")
    ap.add_argument("--listen", action="store_true",
                    help="Just listen for HID input (no send) — useful if device already active")
    ap.add_argument("--listen-time", type=int, default=30,
                    help="Seconds to listen (with --listen, default: 30)")
    args = ap.parse_args()

    if args.listen:
        just_listen(args.listen_time)
    elif args.probe:
        probe_known_patterns()
    else:
        if not Path(args.capture_file).exists():
            print(f"File not found: {args.capture_file}")
            print("Run capture_hid_init.py first, or use --probe to try known patterns.")
            sys.exit(1)
        replay_from_file(args.capture_file)


if __name__ == "__main__":
    main()
