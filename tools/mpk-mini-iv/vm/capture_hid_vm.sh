#!/bin/bash
# Capture HID traffic from MPK mini IV while Windows VM has it via USB passthrough.
# usbmon operates at the host kernel USB bus level — it sees everything.
#
# Run BEFORE launching the Windows VM:
#   Terminal 1: bash capture_hid_vm.sh      ← this script
#   Terminal 2: bash run_vm.sh
#
# The activation packet will appear here when the Akai editor starts in Windows.

set -e

# Ensure usbmon is loaded
if ! lsmod | grep -q usbmon; then
    echo "Loading usbmon kernel module..."
    sudo modprobe usbmon
fi

# Find MPK mini IV bus
MPK_LINE=$(lsusb -d 09e8:005d 2>/dev/null | head -1)
if [ -z "$MPK_LINE" ]; then
    echo "ERROR: MPK mini IV not plugged in. Connect it, then re-run."
    exit 1
fi

BUS=$(echo "$MPK_LINE" | grep -oP '(?<=Bus )\d+')
DEV=$(echo "$MPK_LINE" | grep -oP '(?<=Device )\d+')
BUS_N=$((10#$BUS))  # strip leading zero

echo "MPK mini IV: Bus $BUS Device $DEV"
echo ""

USBMON="/dev/usbmon${BUS_N}"
if [ ! -r "$USBMON" ]; then
    echo "Making $USBMON readable..."
    sudo chmod a+r "$USBMON"
fi

OUTFILE="$(dirname "$0")/../hid_captures.txt"
echo "Output: $OUTFILE"
echo ""
echo "=========================================="
echo "  Capture ready — start run_vm.sh now"
echo "  Then install & run Akai editor in VM"
echo "=========================================="
echo ""

# Use the Python capture script (updated for current device address)
cd "$(dirname "$0")/.."
python3 capture_hid_init.py \
    --bus "$BUS_N" \
    --dev "$((10#$DEV))" \
    --out "$OUTFILE" \
    --verbose
