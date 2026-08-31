#!/usr/bin/env bash
# Phase 0 host capability check for the Muse VM assistant prototype.
# Exits non-zero and prints a reason if the host can't safely take a new
# guest of the requested size right now.
set -euo pipefail

REQUESTED_MEM_MB="${1:-4096}"
REQUIRED_CPU_FLAG="${2:-}"
MIN_DISK_GB=20

fail() { echo "CAPABILITY CHECK FAILED: $1" >&2; exit 1; }

echo "=== virtualization ==="
lscpu | grep -i virtualization || fail "no virtualization extensions reported by lscpu"

if [ -n "$REQUIRED_CPU_FLAG" ]; then
  echo
  echo "=== cpu flag: $REQUIRED_CPU_FLAG ==="
  if grep -qw "$REQUIRED_CPU_FLAG" /proc/cpuinfo; then
    echo "present"
  else
    fail "host CPU is missing required flag '$REQUIRED_CPU_FLAG' (check with: grep -o \"$REQUIRED_CPU_FLAG\" /proc/cpuinfo)"
  fi
fi

echo
echo "=== kvm module ==="
kvm_line=$(lsmod | grep '^kvm' || true)
[ -n "$kvm_line" ] || fail "kvm module not loaded"
lsmod | grep kvm || true

echo
echo "=== memory ==="
free -h
avail_mb=$(free -m | awk '/^Mem:/{print $7}')
if [ "$avail_mb" -lt "$REQUESTED_MEM_MB" ]; then
  fail "only ${avail_mb}MiB available, guest wants ${REQUESTED_MEM_MB}MiB. Free up memory (close browsers/apps) and retry."
fi

echo
echo "=== disk (home) ==="
df -h ~
avail_gb=$(df -BG --output=avail ~ | tail -1 | tr -dc '0-9')
if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
  fail "only ${avail_gb}GB free on \$HOME filesystem, need at least ${MIN_DISK_GB}GB"
fi

echo
echo "CAPABILITY CHECK OK: ${avail_mb}MiB available (>= ${REQUESTED_MEM_MB}MiB requested), ${avail_gb}GB disk free"
