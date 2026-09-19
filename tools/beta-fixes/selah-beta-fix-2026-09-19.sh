#!/usr/bin/env bash
# ============================================================
# selah-beta-fix-2026-09-19 — one-shot fixes for SelahOS Beta 2.0.1
# installs, from the first outside tester's report (17.09.2026).
#
# These are bugs in the installer that are already fixed in source for
# the next ISO. This script brings an ALREADY-INSTALLED system in line
# without a reinstall. Idempotent: safe to run twice.
#
#   sudo bash selah-beta-fix-2026-09-19.sh --check    report only
#   sudo bash selah-beta-fix-2026-09-19.sh            apply the fixes
#
# What it does:
#   1. pacman.conf   remove [selahos-offline] (a live-ISO-only path) and
#                    [chaotic-aur] (no signing key on the installed
#                    system). Either one makes `pacman -Sy` abort, so
#                    updates fail until they are gone.
#   2. Wi-Fi driver  on machines with NO Broadcom Wi-Fi chip, stop the
#                    Broadcom `wl` driver auto-loading. It matches any
#                    Wi-Fi card by PCI class, taints the kernel and
#                    prints a warning on Intel/Atheros/etc. laptops.
#                    Machines that DO have a Broadcom chip are left alone.
#   3. Packages      wireless-regdb (correct Wi-Fi region / 6 GHz),
#                    rtkit + realtime-privileges (PipeWire realtime
#                    audio), ksystemlog + discover (log viewer and
#                    software centre).
#
# Every file it changes is copied to /var/backups/selah-beta-fix/ first.
# Copyright (C) 2026 Selah Technologies LLC
# ============================================================
set -uo pipefail

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

PACMAN_CONF="${SELAH_FIX_PACMAN_CONF:-/etc/pacman.conf}"
BLACKLIST="${SELAH_FIX_BLACKLIST:-/etc/modprobe.d/selah-broadcom.conf}"
BACKUP_DIR="/var/backups/selah-beta-fix"

if [ "$CHECK" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Run as root:  sudo bash $0        (or add --check to only look)"
    exit 1
fi

changed=0; problems=0
say()  { printf '%s\n' "$*"; }
ok()   { say "  [ok]      $*"; }
need() { say "  [needed]  $*"; problems=$((problems+1)); }
did()  { say "  [fixed]   $*"; changed=$((changed+1)); }

backup() {
    [ -e "$1" ] || return 0
    mkdir -p "$BACKUP_DIR"
    cp -a "$1" "$BACKUP_DIR/$(basename "$1").$(date +%Y%m%d-%H%M%S)"
}

say "SelahOS beta fix 2026-09-19 $([ "$CHECK" -eq 1 ] && echo '(check only — nothing will be changed)')"
say

# ---- 1. pacman.conf ------------------------------------------------
say "1. pacman repositories"
for repo in selahos-offline chaotic-aur; do
    if grep -qE "^\[$repo\]" "$PACMAN_CONF" 2>/dev/null; then
        if [ "$CHECK" -eq 1 ]; then
            need "[$repo] is enabled in $PACMAN_CONF and breaks 'pacman -Sy'"
        else
            backup "$PACMAN_CONF"
            # comment out the header and every non-comment line up to the next [section]
            awk -v r="[$repo]" '
                /^\[/ { skip = ($0 == r) ; if (skip) { print "# SelahOS: " r " disabled on installed systems (beta fix 2026-09-19)"; next } }
                skip && $0 !~ /^[[:space:]]*(#|$)/ { next }
                { print }
            ' "$PACMAN_CONF" > "$PACMAN_CONF.new" && mv "$PACMAN_CONF.new" "$PACMAN_CONF"
            did "removed [$repo] from $PACMAN_CONF"
        fi
    else
        ok "[$repo] not enabled"
    fi
done

# ---- 2. Broadcom wl blacklist -------------------------------------
say "2. Wi-Fi driver"
has_broadcom_wifi=0
for dev in /sys/bus/pci/devices/*; do
    [ -e "$dev/vendor" ] || continue
    [ "$(cat "$dev/vendor")" = "0x14e4" ] || continue
    case "$(cat "$dev/class")" in 0x0280*) has_broadcom_wifi=1 ;; esac
done
if [ "$has_broadcom_wifi" -eq 1 ]; then
    ok "Broadcom Wi-Fi chip present — leaving Wi-Fi driver config untouched"
elif grep -qE '^blacklist wl$' "$BLACKLIST" /etc/modprobe.d/*.conf 2>/dev/null; then
    ok "wl driver already blacklisted"
elif ! lsmod | grep -q '^wl ' && ! pacman -Q broadcom-wl-dkms >/dev/null 2>&1; then
    ok "wl driver not installed"
elif [ "$CHECK" -eq 1 ]; then
    need "wl driver auto-loads on a non-Broadcom Wi-Fi card (kernel taint + warning at boot)"
else
    backup "$BLACKLIST"
    printf '%s\n' \
        '# SelahOS beta fix 2026-09-19: this machine has no Broadcom Wi-Fi chip.' \
        '# The wl module matches any Wi-Fi card by PCI class and taints the kernel.' \
        'blacklist wl' >> "$BLACKLIST"
    did "blacklisted wl in $BLACKLIST (takes effect at next boot)"
    lsmod | grep -q '^wl ' && rmmod wl 2>/dev/null && say "            unloaded wl from the running kernel"
fi

# ---- 3. packages ---------------------------------------------------
say "3. packages"
missing=()
for p in wireless-regdb rtkit realtime-privileges ksystemlog discover; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ "${#missing[@]}" -eq 0 ]; then
    ok "all present"
elif [ "$CHECK" -eq 1 ]; then
    need "missing packages: ${missing[*]}"
else
    say "            installing: ${missing[*]}"
    if pacman -Sy --needed --noconfirm "${missing[@]}"; then
        did "installed ${missing[*]}"
    else
        say "  [FAILED]  pacman could not install them — check your network, then run this script again."
        problems=$((problems+1))
    fi
fi

say
if [ "$CHECK" -eq 1 ]; then
    [ "$problems" -eq 0 ] && say "Nothing to fix." || say "$problems item(s) would be fixed. Run without --check to apply."
else
    say "Done: $changed change(s) made. Backups (if any): $BACKUP_DIR"
    [ "$changed" -gt 0 ] && say "Reboot once so the Wi-Fi driver change and realtime audio take effect."
fi
exit 0
