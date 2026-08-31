#!/usr/bin/env bash
# selah-vm-assistant.sh — unified chooser for SelahOS's VM test tooling.
#
# Usage:
#   selah-vm-assistant.sh windows [10|11]   (default: 10 — the working guest;
#                                             11 has an unresolved boot crash,
#                                             see RESUME-LOG-2026-08-28.md)
#   selah-vm-assistant.sh macos <version>   (mojave|catalina|bigsur|monterey|ventura|sonoma|sequoia|tahoe)
#   selah-vm-assistant.sh status            (virsh list --all, selah-* domains only)
#
# Runs the Phase 0 capability check first (via the dispatched script) and
# refuses to proceed if the host doesn't have the headroom for the requested
# guest. Fixed 08-29: this chooser's `windows` branch used to dispatch to
# selah-vm-windows.sh (Windows 11, still broken) instead of the actually
# working selah-vm-windows10.sh — silently kicking off a known-broken install
# any time someone ran `selah-vm-assistant.sh windows` expecting the working
# Windows 10 guest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND="${1:-}"

if [ -z "$KIND" ]; then
  echo "Which guest do you want to build?"
  select choice in windows macos status; do
    KIND="$choice"
    break
  done
fi

case "$KIND" in
  windows)
    WIN_VERSION="${2:-10}"
    case "$WIN_VERSION" in
      10)
        bash "$SCRIPT_DIR/selah-vm-windows10.sh"
        ;;
      11)
        echo "NOTE: Windows 11 has an unresolved boot crash (BFSVC/HarddiskVolume1," >&2
        echo "see RESUME-LOG-2026-08-28.md) — proceeding anyway since you asked for it explicitly." >&2
        bash "$SCRIPT_DIR/selah-vm-windows.sh"
        ;;
      *)
        echo "Usage: $0 windows [10|11]" >&2
        exit 1
        ;;
    esac
    echo ""
    echo "Connect via RDP once the guest has an IP:"
    echo "  IP:  virsh --connect qemu:///system domifaddr selah-win${WIN_VERSION}-test"
    echo "  xfreerdp /v:<ip> /u:selah /p:'SelahTest!2026' /cert:ignore"
    ;;
  macos)
    VERSION="${2:-}"
    if [ -z "$VERSION" ]; then
      echo "Which macOS version?"
      grep -v '^#' "$SCRIPT_DIR/macos-versions.conf" | cut -d: -f1
      read -rp "> " VERSION
    fi
    bash "$SCRIPT_DIR/selah-vm-macos.sh" "$VERSION"
    ;;
  status)
    if ! groups | grep -qw libvirt || ! groups | grep -qw kvm; then
      echo "ERROR: current shell is not in the libvirt/kvm groups yet." >&2
      echo "Run: sudo usermod -aG libvirt,kvm \$USER ; then start a new shell" >&2
      exit 1
    fi
    virsh --connect qemu:///system list --all | awk 'NR<=2 || /selah-/'
    ;;
  *)
    echo "Usage: $0 {windows [10|11]|macos <version>|status}" >&2
    exit 1
    ;;
esac
