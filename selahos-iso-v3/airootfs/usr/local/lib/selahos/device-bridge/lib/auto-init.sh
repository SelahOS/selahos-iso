#!/bin/bash
#
# SelahOS Device Bridge - Boot-time auto-initialization
# Called by systemd service on boot to initialize any connected devices
#

set -e

LOG_FILE="/var/log/selahos-device-bridge.log"
LIB_DIR="/usr/local/lib/selahos/device-bridge"
PYTHON3=$(which python3)

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Log function
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [boot] $1" >> "$LOG_FILE"
}

log_msg "SelahOS Device Bridge Boot Initialization"
log_msg "========================================"

# Wait for USB devices to be enumerated
sleep 3

# Function to check if device is connected
device_connected() {
    local vid="$1"
    local pid="$2"
    lsusb 2>/dev/null | grep -q "$vid:$pid"
    return $?
}

# MPK mini IV (VID_09E8:PID_005D)
if device_connected "09e8" "005d"; then
    log_msg "Found MPK mini IV - initializing..."
    if [ -f "$LIB_DIR/mpk_mini_iv.py" ]; then
        "$PYTHON3" "$LIB_DIR/mpk_mini_iv.py" --init >> "$LOG_FILE" 2>&1 && \
            log_msg "✓ MPK mini IV ready" || \
            log_msg "⚠ MPK mini IV initialization had issues"
    fi
fi

# MPC Studio mk2 (VID_09E8:PID_004A)
if device_connected "09e8" "004a"; then
    log_msg "Found MPC Studio mk2 - initializing..."
    if [ -f "$LIB_DIR/mpc_studio2_mk2.py" ]; then
        "$PYTHON3" "$LIB_DIR/mpc_studio2_mk2.py" --init >> "$LOG_FILE" 2>&1 && \
            log_msg "✓ MPC Studio mk2 ready" || \
            log_msg "⚠ MPC Studio mk2 initialization had issues"
    fi
fi

log_msg "Boot initialization complete"
log_msg ""

exit 0
