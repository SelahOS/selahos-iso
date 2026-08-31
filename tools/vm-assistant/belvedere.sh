#!/usr/bin/env bash
# Launches Belvedere, the SelahOS VM Manager GUI. One command, matching the
# CLI scripts' own ethos — no manual venv activation needed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BELVEDERE_DIR="$SCRIPT_DIR/belvedere"

if [ ! -d "$BELVEDERE_DIR/.venv" ]; then
  echo "Setting up Belvedere's environment (first run only)..."
  python3 -m venv --system-site-packages "$BELVEDERE_DIR/.venv"
  "$BELVEDERE_DIR/.venv/bin/pip" install --quiet PySide6
fi

if ! groups | grep -qw libvirt || ! groups | grep -qw kvm; then
  echo "ERROR: current shell is not in the libvirt/kvm groups yet." >&2
  echo "Run: sudo usermod -aG libvirt,kvm \$USER ; then start a new shell" >&2
  exit 1
fi

cd "$BELVEDERE_DIR"
# QT_QPA_PLATFORM=xcb: this host's Wayland session doesn't expose a working
# wl_display for a plain venv-launched Qt app; X11 (via XWayland) works.
exec env QT_QPA_PLATFORM=xcb "$BELVEDERE_DIR/.venv/bin/python3" main.py
