#!/usr/bin/env bash
# wifi_calibration_probe.sh -- diagnostic + low-risk try for the MacBook10,1
# BCM4350c2 Wi-Fi "connecting (configuring)" hang seen on Beta 2.0.1.
#
# CONTEXT (see selahos-iso-v3/docs/hardware-lab/wifi-macbook10-1-calibration.md
# for the full writeup): brcmfmac can't find a per-board NVRAM/CLM/txcap file
# for this exact chip (Apple Inc. Device 0131), and logs "no clm_blob
# available ... device may have limited channels available". Upstream kernel
# treats a missing CLM blob as non-fatal (falls back to the chip's own OTP
# calibration with a restricted channel set) -- so the missing file alone
# probably isn't the WHOLE story. A restricted/wrong channel set is a
# plausible reason an association attempt could hang instead of failing
# cleanly, especially against a 5GHz-capable AP.
#
# This script does NOT install a fabricated calibration file -- no verified
# one exists yet, and shipping a wrong one is worse than shipping none. It
# instead: (1) explicitly sets a regulatory domain, since "no clm_blob"
# threads commonly cite this as the practical fix, and (2) captures a real,
# detailed log of the next connection attempt so we get hard evidence
# instead of guessing further if this alone doesn't fix it.
#
# USAGE (run locally with sudo, or over SSH -- this doesn't touch /dev/snd
# so the SSH device-cgroup restriction that blocks gpio_poke.py doesn't
# apply here):
#   sudo bash wifi_calibration_probe.sh
#
# Then try connecting to Wi-Fi again and watch for the association to
# actually complete. A log of the attempt is written to
# ~/selahos-wifi-probe-<timestamp>.log -- send that back regardless of
# whether this fixes it.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root (sudo bash $0)." >&2
    exit 1
fi

LOG="$HOME/selahos-wifi-probe-$(date +%Y%m%d-%H%M%S).log"
echo "Logging to $LOG"

{
    echo "=== before: current regulatory domain ==="
    iw reg get || true

    echo
    echo "=== setting regulatory domain to US ==="
    echo "(edit this script and change 'US' first if you're not in the US --"
    echo " a wrong country code can be as bad as no CLM blob at all)"
    iw reg set US
    sleep 1
    iw reg get

    echo
    echo "=== supported channels/frequencies after reg set ==="
    iw phy phy0 channels 2>/dev/null || iw list | grep -A200 "Wiphy phy0" | grep -E "MHz|channels"

    echo
    echo "=== restarting brcmfmac to pick up the new reg domain cleanly ==="
    nmcli radio wifi off || true
    modprobe -r brcmfmac || echo "modprobe -r failed (module in use?) -- continuing anyway"
    sleep 2
    modprobe brcmfmac
    sleep 3
    nmcli radio wifi on
    sleep 2

    echo
    echo "=== now try connecting from the GUI or: nmcli device wifi connect <SSID> --ask ==="
    echo "=== this script will tail the kernel + NetworkManager logs for 60s -- go connect now ==="
    timeout 60 journalctl -k -f &
    JPID=$!
    timeout 60 journalctl -u NetworkManager -f &
    NPID=$!
    wait $JPID $NPID 2>/dev/null || true

    echo
    echo "=== final device state ==="
    nmcli device status
    ip link show

} 2>&1 | tee "$LOG"

echo
echo "Done. Whether or not it connected, send back: $LOG"
