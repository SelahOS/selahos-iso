#!/usr/bin/env python3
"""
gpio_poke.py -- poke the CS4208 AFG's GPIO_DATA register directly via the
raw HDA hwdep ioctl, hunting for a GPIO bit pattern that actually enables
the internal-speaker amp on MacBook10,1 (12-inch MacBook, 2017).

EXPERIMENTAL / DIAGNOSTIC ONLY. Every register the shipped driver
(macbook12-audio-driver, juicecultus fork) touches is already in the
state it intends -- GPIO0 high, GPIO4/5 configured as outputs but held
low -- and the speaker is still silent. This script exists to try other
bit patterns live, in seconds, instead of a full source-edit/rebuild/
reboot cycle per guess. See selahos-iso-v3/docs/hardware-lab/
cs4208-gpio-investigation.md for the full history.

MUST run from a local desktop terminal on the target machine, NOT over
SSH -- a systemd device-cgroup policy restricts raw /dev/snd/hwC*D0
access to the active graphical (seat0) session. It will fail with
PermissionError over SSH even though file permissions/ACLs look fine.

Usage:
    python3 gpio_poke.py <hex-byte>

Recommended procedure:
    1. In one local terminal: speaker-test -D default -c2 -t sine -f 440 -l 0
       (leave it running continuously)
    2. In another local terminal, try each value below in turn, listening
       after each one:
         python3 gpio_poke.py 0x31   # bits 0,4,5 all high (close to shipped default)
         python3 gpio_poke.py 0x11   # bits 0,4 high
         python3 gpio_poke.py 0x21   # bits 0,5 high
         python3 gpio_poke.py 0x30   # bits 4,5 high, bit 0 LOW (inverts the current driver's bit 0)
         python3 gpio_poke.py 0x10   # bit 4 only
         python3 gpio_poke.py 0x20   # bit 5 only
         python3 gpio_poke.py 0x00   # all low
    3. If ANY value produces audible sound, stop and report the exact
       value -- do not keep going past a hit. That value needs to be
       ported into play_a1534() (and the matching speaker-return branch
       in cs_4208_hp_jack_callback) in patch_cirrus_a1534_setup.h, then a
       real rebuild+reboot to make it permanent.
    4. If nothing in this list works, this points toward a physical
       fault in this specific unit rather than a software/polarity
       issue -- worth checking the internal speaker connector/cable
       seating before trying further bit combinations.
"""
import fcntl
import glob
import struct
import sys

# _IOWR('H', 0x11, struct hda_verb_ioctl { unsigned int verb; unsigned int res; })
# Confirmed against the real kernel headers on the MacBook10,1 test machine.
HDA_IOCTL_VERB_WRITE = 0xC0084811

AFG_NID = 0x01
AC_VERB_SET_GPIO_DATA = 0x715


def hda_verb(nid: int, verb: int, param: int) -> int:
    return (nid << 24) | (verb << 8) | param


def find_hwdep() -> str:
    candidates = sorted(glob.glob("/dev/snd/hwC*D0"))
    if not candidates:
        print("No /dev/snd/hwC*D0 device found -- is the sound card up?")
        sys.exit(1)
    return candidates[0]


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <hex-byte, e.g. 0x31>")
        sys.exit(1)

    try:
        data = int(sys.argv[1], 16) & 0xFF
    except ValueError:
        print(f"'{sys.argv[1]}' isn't a valid hex byte (try 0x31, 0x00, ...)")
        sys.exit(1)

    dev_path = find_hwdep()
    verb = hda_verb(AFG_NID, AC_VERB_SET_GPIO_DATA, data)
    buf = bytearray(struct.pack("=II", verb, 0))

    try:
        with open(dev_path, "rb+", buffering=0) as f:
            fcntl.ioctl(f.fileno(), HDA_IOCTL_VERB_WRITE, buf, True)
    except PermissionError:
        print(
            f"PermissionError opening {dev_path}. This almost always means "
            "you're running this over SSH -- run it from a terminal inside "
            "your actual local desktop session on this machine instead."
        )
        sys.exit(1)

    _res_verb, res_val = struct.unpack("=II", buf)
    print(
        f"Wrote GPIO_DATA=0x{data:02x} via {dev_path} "
        f"(verb=0x{verb:08x}) -> response=0x{res_val:08x}"
    )
    print("Listen now. Ctrl+C the speaker-test terminal once you've checked this value.")


if __name__ == "__main__":
    main()
