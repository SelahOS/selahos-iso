#!/usr/bin/env python3
"""
gpio_poke_cs4206.py -- poke the Cirrus CS4206 AFG's GPIO registers directly
via the raw HDA hwdep ioctl, hunting for a bit pattern that actually
enables the internal-speaker amp on the 2012 MacBook Pro (MacBookPro9,2,
non-Retina 13").

EXPERIMENTAL / DIAGNOSTIC ONLY. This codec's own capability report says
GPIO: io=4 (4 total pins, bits 0-3). The currently-loaded driver applies
the generic Apple fallback fixup (cs420x_fixup_gpio_13): GPIO1 = headphone
EAPD, GPIO3 = speaker EAPD, both driven high -- confirmed via live codec
dump (`Pin-ctls`/GPIO IO[1] and IO[3] both enable=1 dir=1 data=1) -- and
the internal speaker is still silent despite this being verbatim what the
driver intends. Unlike the CS4208 script, this one ALSO sets GPIO_MASK and
GPIO_DIRECTION every run (not just GPIO_DATA), so it can freely test the
two currently-unused pins (GPIO0, GPIO2) too, not only the two the driver
already touches.

MUST run from a local desktop terminal on the target machine, NOT over
SSH -- a systemd device-cgroup policy restricts raw /dev/snd/hwC*D0
access to the active graphical (seat0) session. It will fail with
PermissionError over SSH even though file permissions/ACLs look fine.

Usage:
    python3 gpio_poke_cs4206.py <hex-byte, 0x00-0x0F -- only bits 0-3 exist>

Recommended procedure:
    1. In one local terminal: speaker-test -D default -c2 -t sine -f 440 -l 0
       (leave it running continuously)
    2. In another local terminal, try each value below in turn, listening
       after each one:
         python3 gpio_poke_cs4206.py 0x0A   # current driver default (GPIO1+3 high) -- baseline, already confirmed silent
         python3 gpio_poke_cs4206.py 0x08   # GPIO3 (speaker) only, drop headphone-enable
         python3 gpio_poke_cs4206.py 0x02   # GPIO1 (headphone) only
         python3 gpio_poke_cs4206.py 0x00   # all low -- inverted-polarity guess
         python3 gpio_poke_cs4206.py 0x0F   # all 4 pins high, including the two currently unused
         python3 gpio_poke_cs4206.py 0x05   # GPIO0+GPIO2 high instead (the two currently-unused pins) -- polarity-swap guess
         python3 gpio_poke_cs4206.py 0x0D   # everything except GPIO1 (headphone) high
         python3 gpio_poke_cs4206.py 0x07   # everything except GPIO3 (speaker) high
    3. If ANY value produces audible sound, stop and report the exact
       value -- do not keep going past a hit. Whatever value works needs
       to be ported into a real fixup (either a new SSID-specific entry in
       cs420x_fixup_tbl for subsystem ID 0x106b5200, or by adjusting
       cs420x_fixup_gpio_13 if it turns out the generic fallback's
       GPIO1/GPIO3 assumption is simply wrong for this board), then a real
       rebuild+reboot to make it permanent.
    4. If nothing in this list works, this points toward a physical fault
       in this specific 12+ year old unit rather than a software/polarity
       issue -- the driver logic itself already checks out correct.
"""
import fcntl
import glob
import struct
import sys

# _IOWR('H', 0x11, struct hda_verb_ioctl { unsigned int verb; unsigned int res; })
# Confirmed against the real kernel headers on MacBook10,1; same ioctl
# number applies to any HDA hwdep node regardless of codec.
HDA_IOCTL_VERB_WRITE = 0xC0084811

AFG_NID = 0x01
AC_VERB_SET_GPIO_DATA = 0x715
AC_VERB_SET_GPIO_DIRECTION = 0x716
AC_VERB_SET_GPIO_MASK = 0x717

ALL_FOUR_PINS = 0x0F  # bits 0-3 -- this codec's io=4 means only these exist


def hda_verb(nid: int, verb: int, param: int) -> int:
    return (nid << 24) | (verb << 8) | param


def find_hwdep() -> str:
    candidates = sorted(glob.glob("/dev/snd/hwC*D0"))
    if not candidates:
        print("No /dev/snd/hwC*D0 device found -- is the sound card up?")
        sys.exit(1)
    return candidates[0]


def send_verb(f, nid: int, verb: int, param: int) -> int:
    buf = bytearray(struct.pack("=II", hda_verb(nid, verb, param), 0))
    fcntl.ioctl(f.fileno(), HDA_IOCTL_VERB_WRITE, buf, True)
    _res_verb, res_val = struct.unpack("=II", buf)
    return res_val


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <hex-byte, e.g. 0x0A -- only bits 0-3 are real>")
        sys.exit(1)

    try:
        data = int(sys.argv[1], 16) & ALL_FOUR_PINS
    except ValueError:
        print(f"'{sys.argv[1]}' isn't a valid hex byte (try 0x0A, 0x00, ...)")
        sys.exit(1)

    dev_path = find_hwdep()

    try:
        with open(dev_path, "rb+", buffering=0) as f:
            # Enable all 4 pins as outputs so any bit pattern is testable,
            # not just the two (GPIO1, GPIO3) the current driver already
            # configures.
            send_verb(f, AFG_NID, AC_VERB_SET_GPIO_MASK, ALL_FOUR_PINS)
            send_verb(f, AFG_NID, AC_VERB_SET_GPIO_DIRECTION, ALL_FOUR_PINS)
            res_val = send_verb(f, AFG_NID, AC_VERB_SET_GPIO_DATA, data)
    except PermissionError:
        print(
            f"PermissionError opening {dev_path}. This almost always means "
            "you're running this over SSH -- run it from a terminal inside "
            "your actual local desktop session on this machine instead."
        )
        sys.exit(1)

    print(
        f"Wrote GPIO_DATA=0x{data:02x} (mask+dir=0x{ALL_FOUR_PINS:02x}) "
        f"via {dev_path} -> response=0x{res_val:08x}"
    )
    print("Listen now. Ctrl+C the speaker-test terminal once you've checked this value.")


if __name__ == "__main__":
    main()
