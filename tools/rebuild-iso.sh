#!/usr/bin/env bash
# rebuild-iso.sh — clean rebuild of the SelahOS ISO from selahos-iso-v3,
# then run the pre-flash preflight gate against the result.
#
# Usage: sudo bash ~/SelahOS-Dev/tools/rebuild-iso.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

WORK=/home/dbnoble/selahos-work
OUT=/home/dbnoble/selahos-iso-output
PROFILE=/home/dbnoble/SelahOS-Dev/selahos-iso-v3/
LOG=/home/dbnoble/selahos-build-log.txt

echo "==> Removing stale work/output dirs"
rm -rf "$WORK" "$OUT"

echo "==> Building offline package repo (bundled on the ISO for network-free installs, log: $LOG)"
bash /home/dbnoble/SelahOS-Dev/tools/build-offline-repo.sh 2>&1 | tee "$LOG"

echo "==> Building ISO (log: $LOG)"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE" 2>&1 | tee -a "$LOG"

echo
echo "==> Build finished, running preflight gate (log: $LOG)"
bash /home/dbnoble/SelahOS-Dev/tools/iso-preflight.sh 2>&1 | tee -a "$LOG"
