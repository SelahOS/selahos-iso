#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  install-selahbridgepro.sh — SelahBridgePro v1 System Installer
#  Installs from a local clone of github.com/SelahOS/selahos-iso
#  Selah Technologies LLC — Copyright (C) 2026
#
#  Usage (on the SelahOS machine):
#    git clone https://github.com/SelahOS/selahos-iso ~/selahos-iso-repo
#    cd ~/selahos-iso-repo
#    sudo bash install-selahbridgepro.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

GOLD=$'\033[38;2;214;168;90m'
PARCH=$'\033[38;2;237;228;212m'
TEAL=$'\033[38;2;142;195;184m'
MUTED=$'\033[38;2;154;141;123m'
RED=$'\033[38;2;185;122;111m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

ok()   { printf '  %s✓%s %s%s%s\n'   "$TEAL"  "$RESET" "$PARCH" "$1" "$RESET"; }
info() { printf '  %s→ %s%s\n'        "$MUTED" "$1" "$RESET"; }
warn() { printf '  %s⚠  %s%s%s\n'   "$RED"   "$RESET" "$PARCH" "$1" "$RESET"; }
die()  { printf '\n%s✗  %s%s\n'      "$RED"   "$1" "$RESET" >&2; exit 1; }
hdr()  { printf '\n%s%s══  %s  ══%s\n' "$GOLD" "$BOLD" "$1" "$RESET"; }

# ── Must run as root ─────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo bash install-selahbridgepro.sh"
REAL_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$REAL_USER" && "$REAL_USER" != "root" ]] || \
    die "Run via sudo from your normal user account, not directly as root"

# ── Locate source root (where this script lives) ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/selahos-iso-v3/airootfs"
[[ -d "$SRC" ]] || die "Source airootfs not found at $SRC — run from the repo root"

clear
printf '%s%s\n' "$GOLD" "$BOLD"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════════════════╗
  ║        SelahBridgePro™  v1  —  System Installer              ║
  ║   Wine · DXVK · SelahASIO · USB MIDI · for SelahOS           ║
  ╚══════════════════════════════════════════════════════════════╝
BANNER
printf '%s' "$RESET"
printf '  %sInstalling for:%s %s%s%s\n' "$MUTED" "$RESET" "$PARCH" "$REAL_USER" "$RESET"

# ── Step 1: Python + PyQt6 dependencies ──────────────────────────────────────
hdr "Installing Python / PyQt6 dependencies"

PKGS_NEEDED=()
for pkg in python python-pyqt6; do
    pacman -Qi "$pkg" &>/dev/null || PKGS_NEEDED+=("$pkg")
done

if [[ ${#PKGS_NEEDED[@]} -gt 0 ]]; then
    info "Installing: ${PKGS_NEEDED[*]}"
    pacman -S --noconfirm --needed "${PKGS_NEEDED[@]}"
fi
ok "python + python-pyqt6 ready"

# python-pyqt6-webengine is optional (selahauth fallback to xdg-open if absent)
if ! pacman -Qi python-pyqt6-webengine &>/dev/null; then
    info "Installing python-pyqt6-webengine (selahauth browser)..."
    pacman -S --noconfirm --needed python-pyqt6-webengine 2>/dev/null || \
        warn "python-pyqt6-webengine not available — selahauth will use system browser"
else
    ok "python-pyqt6-webengine ready"
fi

# python-rtmidi is required by selah-mpc-bridge
if ! python -c "import rtmidi" &>/dev/null 2>&1; then
    info "Installing python-rtmidi (selah-mpc-bridge)..."
    pip install python-rtmidi --quiet || \
        warn "python-rtmidi install failed — selah-mpc-bridge will not work"
else
    ok "python-rtmidi ready"
fi

# ── Step 2: Copy executables ──────────────────────────────────────────────────
hdr "Installing executables"

install -Dm755 "$SRC/usr/local/bin/selahpro"          /usr/local/bin/selahpro
ok "selahpro"
install -Dm755 "$SRC/usr/local/bin/selahbridgepro"    /usr/local/bin/selahbridgepro
ok "selahbridgepro"
install -Dm755 "$SRC/usr/local/bin/selahwine"         /usr/local/bin/selahwine
ok "selahwine"
install -Dm755 "$SRC/usr/local/bin/selah-asio-config" /usr/local/bin/selah-asio-config
ok "selah-asio-config"
install -Dm755 "$SRC/usr/local/bin/selahauth"         /usr/local/bin/selahauth
ok "selahauth"
install -Dm755 "$SRC/usr/local/bin/selah-mpc-bridge" /usr/local/bin/selah-mpc-bridge
ok "selah-mpc-bridge"

# ── Step 3: Config and profiles ──────────────────────────────────────────────
hdr "Installing profiles and config"

install -d /etc/selahbridgepro/profiles
install -Dm644 "$SRC/etc/selahbridgepro/selahbridgepro.conf" \
               /etc/selahbridgepro/selahbridgepro.conf
ok "selahbridgepro.conf"

for profile in "$SRC"/etc/selahbridgepro/profiles/*.profile; do
    install -Dm644 "$profile" "/etc/selahbridgepro/profiles/$(basename "$profile")"
    ok "profile: $(basename "$profile")"
done

# MPC Studio 2 bridge config (only written if not already present)
install -d /etc/selah-mpc
if [[ ! -f /etc/selah-mpc/mpc-studio2.conf ]]; then
    install -Dm644 "$SRC/etc/selah-mpc/mpc-studio2.conf" \
                   /etc/selah-mpc/mpc-studio2.conf
    ok "mpc-studio2.conf"
else
    ok "mpc-studio2.conf (already present — not overwritten)"
fi

# ── Step 4: Shared data files ─────────────────────────────────────────────────
hdr "Installing shared data"

install -d /usr/share/selahbridgepro
install -Dm644 "$SRC/usr/share/selahbridgepro/selahwine-defaults.reg" \
               /usr/share/selahbridgepro/selahwine-defaults.reg
ok "selahwine-defaults.reg"
install -Dm644 "$SRC/usr/share/selahbridgepro/selahwine-dp-fixes.reg" \
               /usr/share/selahbridgepro/selahwine-dp-fixes.reg
ok "selahwine-dp-fixes.reg"

# ── Step 5: Desktop entries ───────────────────────────────────────────────────
hdr "Installing desktop entries"

install -Dm644 "$SRC/usr/share/applications/selahbridgepro.desktop" \
               /usr/share/applications/selahbridgepro.desktop
ok "selahbridgepro.desktop"
install -Dm644 "$SRC/usr/share/applications/selahauth.desktop" \
               /usr/share/applications/selahauth.desktop
ok "selahauth.desktop"

# Copy selahbridge icon so the app window has one
for res in 256x256 128x128 48x48; do
    icon="$SRC/usr/share/icons/hicolor/${res}/apps/selahbridge.png"
    [[ -f "$icon" ]] && \
        install -Dm644 "$icon" "/usr/share/icons/hicolor/${res}/apps/selahbridge.png"
done
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
ok "icons"

# Update desktop database so KDE sees the new entry immediately
update-desktop-database /usr/share/applications 2>/dev/null || true

# ── Step 6: udev MIDI rules ───────────────────────────────────────────────────
hdr "Installing USB MIDI udev rules"

install -Dm644 "$SRC/etc/udev/rules.d/99-selah-midi.rules" \
               /etc/udev/rules.d/99-selah-midi.rules
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb 2>/dev/null || true
ok "udev rules installed and reloaded"

# ── Step 7: Realtime audio privileges ────────────────────────────────────────
hdr "Configuring realtime audio privileges"

LIMITS="/etc/security/limits.conf"
if ! grep -q "@audio.*rtprio" "$LIMITS" 2>/dev/null; then
    printf '\n# SelahBridgePro realtime audio\n@audio  -  rtprio   88\n@audio  -  memlock  unlimited\n' \
        >> "$LIMITS"
    ok "Realtime limits added"
else
    ok "Realtime limits already set"
fi

if ! groups "$REAL_USER" | grep -q audio; then
    usermod -aG audio,realtime "$REAL_USER" 2>/dev/null || \
        usermod -aG audio "$REAL_USER" 2>/dev/null || true
    info "Added $REAL_USER to audio group — re-login required"
else
    ok "$REAL_USER already in audio group"
fi

# ── Step 8: selah-mpc-bridge systemd user service ────────────────────────────
hdr "Installing MPC bridge service"

install -Dm644 "$SRC/usr/lib/systemd/user/selah-mpc-bridge.service" \
               /usr/lib/systemd/user/selah-mpc-bridge.service
ok "selah-mpc-bridge.service installed"

# Enable for the real user (user services require --user, run as that user)
if su - "$REAL_USER" -c "systemctl --user daemon-reload && \
                         systemctl --user enable selah-mpc-bridge.service" \
   2>/dev/null; then
    ok "selah-mpc-bridge enabled for $REAL_USER (starts on next login)"
    info "To start now: systemctl --user start selah-mpc-bridge"
else
    warn "Could not enable service automatically — run as $REAL_USER:"
    info "  systemctl --user enable --now selah-mpc-bridge"
fi

# ── Step 9: .keydata (trial mode — license key deployed separately) ───────────
hdr "License setup"

install -d /etc/selahbridgepro
if [[ ! -f /etc/selahbridgepro/.keydata ]]; then
    # Empty keydata = trial-only mode (14 days). The app works fully.
    # To activate: run tools/selahpro-keygen-deploy.sh on the build machine,
    # then scp the resulting /etc/selahbridgepro/.keydata to this machine.
    touch /etc/selahbridgepro/.keydata
    chmod 600 /etc/selahbridgepro/.keydata
    info ".keydata created (trial mode — 14 days free)"
    info "To activate: scp the .keydata from your build machine after running"
    info "  bash tools/selahpro-keygen-deploy.sh"
else
    ok ".keydata already present"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n%s%s══════════════════════════════════════════════════════%s\n' \
    "$TEAL" "$BOLD" "$RESET"
printf '  %s%s✓  SelahBridgePro v1 installed successfully%s\n' \
    "$TEAL" "$BOLD" "$RESET"
printf '%s══════════════════════════════════════════════════════%s\n\n' \
    "$TEAL" "$RESET"

printf '  %sLaunch GUI:%s        selahbridgepro\n' "$MUTED" "$RESET"
printf '  %sLaunch CLI:%s        selahpro --help\n' "$MUTED" "$RESET"
printf '  %sDiagnose:%s          selahpro diagnose\n' "$MUTED" "$RESET"
printf '  %sInstall DAW:%s       selahpro install dp\n' "$MUTED" "$RESET"
printf '  %sMPC bridge status:%s systemctl --user status selah-mpc-bridge\n' "$MUTED" "$RESET"
printf '  %sMPC monitor:%s       selah-mpc-bridge monitor\n\n' "$MUTED" "$RESET"
