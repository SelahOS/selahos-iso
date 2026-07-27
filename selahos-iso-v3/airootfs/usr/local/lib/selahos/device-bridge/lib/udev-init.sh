#!/bin/bash
#
# SelahOS Device Bridge - udev initialization script
# Called automatically when Akai device is plugged in
#
# Usage: Called by udev rule, arguments: device_name
#

set -e

DEVICE_NAME="${1:-unknown}"
LOG_FILE="/var/log/selahos-device-bridge.log"
LIB_DIR="/usr/local/lib/selahos/device-bridge"
PYTHON3=$(which python3)

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Log function
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [udev] $1" >> "$LOG_FILE"
}

log_msg "Device connected: $DEVICE_NAME"

# Wait for device to fully enumerate (udev rules run early)
sleep 2

# Run appropriate initializer
case "$DEVICE_NAME" in
    mpk_mini_iv)
        log_msg "Initializing MPK mini IV..."
        if [ -f "$LIB_DIR/mpk_mini_iv.py" ]; then
            "$PYTHON3" "$LIB_DIR/mpk_mini_iv.py" --init >> "$LOG_FILE" 2>&1 && \
                log_msg "✓ MPK mini IV initialized" || \
                log_msg "✗ MPK mini IV initialization failed"
        else
            log_msg "✗ mpk_mini_iv.py not found"
        fi
        ;;

    mpc_studio2_mk2)
        log_msg "Initializing MPC Studio mk2..."
        if [ -f "$LIB_DIR/mpc_studio2_mk2.py" ]; then
            "$PYTHON3" "$LIB_DIR/mpc_studio2_mk2.py" --init >> "$LOG_FILE" 2>&1 && \
                log_msg "✓ MPC Studio mk2 initialized" || \
                log_msg "✗ MPC Studio mk2 initialization failed"
        else
            log_msg "✗ mpc_studio2_mk2.py not found"
        fi
        ;;

    *)
        log_msg "⚠ Unknown device: $DEVICE_NAME"
        ;;
esac

exit 0
