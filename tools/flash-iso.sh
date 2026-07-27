#!/usr/bin/env bash
# flash-iso.sh — write a SelahOS ISO to a USB drive
#
# Usage: sudo bash flash-iso.sh /dev/sdX [path-to-iso]
#   /dev/sdX     — REQUIRED. The whole-disk device for the USB drive
#                  (e.g. /dev/sdc, NOT /dev/sdc1). Run `lsblk` yourself
#                  first to find it — this script never guesses/
#                  auto-detects a target, on purpose.
#   path-to-iso  — optional; defaults to the newest ISO in
#                  ~/selahos-iso-output (same default iso-preflight.sh uses)
#
# THIS IS DESTRUCTIVE: everything on the target device is erased.
# The script refuses to run against a partition, and refuses to run
# against whatever disk is backing the currently running system, but
# it cannot know which USB stick you meant — that's on you via $1.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0 /dev/sdX [path-to-iso]"; exit 1; }

DEV="${1:-}"
if [ -z "$DEV" ]; then
    echo "Usage: sudo bash $0 /dev/sdX [path-to-iso]"
    echo
    echo "Block devices on this machine:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN | sed 's/^/  /'
    exit 1
fi

ISO="${2:-$(ls -t /home/dbnoble/selahos-iso-output/*.iso 2>/dev/null | head -1)}"
[ -f "$ISO" ] || { echo "FAIL: no ISO found (looked for: $ISO)"; exit 1; }

[ -b "$DEV" ] || { echo "FAIL: $DEV is not a block device"; exit 1; }

# Refuse partitions — only whole disks
case "$DEV" in
    *[0-9]) echo "FAIL: $DEV looks like a partition, not a whole disk (use e.g. /dev/sdc, not /dev/sdc1)"; exit 1 ;;
esac

# Refuse the disk backing the currently running system
ROOT_SRC="$(findmnt -n -o SOURCE / || true)"
ROOT_PKNAME="$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null || true)"
if [ -n "$ROOT_PKNAME" ] && [ "$DEV" = "/dev/$ROOT_PKNAME" ]; then
    echo "FAIL: $DEV appears to be the disk this system is running from. Refusing."
    exit 1
fi

echo "About to write:"
echo "  ISO:    $ISO ($(du -h "$ISO" | cut -f1))"
echo "  Target: $DEV"
echo
lsblk "$DEV" -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
echo
echo "THIS WILL ERASE EVERYTHING ON $DEV."
read -rp "Type the device path again to confirm ($DEV): " CONFIRM
[ "$CONFIRM" = "$DEV" ] || { echo "Confirmation did not match — aborting."; exit 1; }

echo "==> Unmounting any mounted partitions on $DEV"
for part in "${DEV}"[0-9]*; do
    [ -b "$part" ] || continue
    umount "$part" 2>/dev/null || true
done

echo "==> Writing $ISO to $DEV (this will take a while — no progress bar until dd catches up)"
dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync oflag=direct
sync

echo
echo "==> Done. Safe to remove after this: sudo eject $DEV"
