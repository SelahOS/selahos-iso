#!/usr/bin/env bash
# ============================================================
# SelahOS Dev Machine Restore
# Reinstalls the full SelahOS theme, SelahBridge, and all
# system configs onto a running SelahOS installation.
# Run from the directory containing selahos-iso-final/
#
# Usage:
#   tar xzf selahos-iso-final.tar.gz
#   cd selahos-iso-final
#   bash restore-dev-machine.sh
# ============================================================

set -e

GOLD='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
AIROOTFS="$PROFILE_DIR/airootfs"

echo ""
echo -e "${GOLD}  SelahOS Dev Machine Restore${NC}"
echo -e "${DIM}  Restoring theme, configs, and SelahBridge...${NC}"
echo ""

# Must run as root for system files, but also need user home
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}  Run with sudo: sudo bash restore-dev-machine.sh${NC}"
    exit 1
fi

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
step() { echo -e "${GOLD}  ──${NC} $1"; }

# ── 1. KDE Theme ─────────────────────────────────────────────
step "Installing Selah color scheme..."
mkdir -p /usr/share/color-schemes
cp "$AIROOTFS/usr/share/color-schemes/Selah.colors" \
   /usr/share/color-schemes/
ok "Selah.colors installed"

step "Installing Kvantum theme..."
mkdir -p /usr/share/Kvantum/Selah
cp -r "$AIROOTFS/usr/share/Kvantum/Selah/"* \
   /usr/share/Kvantum/Selah/
ok "Kvantum Selah theme installed"

step "Installing Plasma desktop theme..."
mkdir -p /usr/share/plasma/desktoptheme/
cp -r "$AIROOTFS/usr/share/plasma/desktoptheme/selah" \
   /usr/share/plasma/desktoptheme/ 2>/dev/null || true
ok "Plasma desktop theme installed"

step "Installing KDE Look-and-Feel package..."
mkdir -p /usr/share/plasma/look-and-feel/
cp -r "$AIROOTFS/usr/share/plasma/look-and-feel/org.selahos.selah" \
   /usr/share/plasma/look-and-feel/ 2>/dev/null || true
ok "Look-and-Feel package installed"

step "Installing SDDM login theme..."
mkdir -p /usr/share/sddm/themes/
cp -r "$AIROOTFS/usr/share/sddm/themes/selah" \
   /usr/share/sddm/themes/
ok "SDDM selah theme installed"

# ── 2. Apply theme to current user ───────────────────────────
step "Applying theme to $REAL_USER..."
mkdir -p "$REAL_HOME/.config/Kvantum"

# Kvantum
cp "$AIROOTFS/etc/skel/.config/Kvantum/kvantum.kvconfig" \
   "$REAL_HOME/.config/Kvantum/kvantum.kvconfig"

# KDE globals
cp "$AIROOTFS/etc/skel/.config/kdeglobals" \
   "$REAL_HOME/.config/kdeglobals"

# Plasma theme
cp "$AIROOTFS/etc/skel/.config/plasmarc" \
   "$REAL_HOME/.config/plasmarc"

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/Kvantum"
ok "Theme applied to $REAL_USER"

# ── 3. SDDM theme activation ─────────────────────────────────
step "Activating SDDM login theme..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-selah-theme.conf << 'EOF'
[Theme]
Current=selah
EOF
ok "SDDM theme activated"

# ── 4. Install Kvantum if missing ────────────────────────────
step "Checking Kvantum..."
if ! command -v kvantummanager &>/dev/null; then
    pacman -S --noconfirm --needed kvantum kvantum-qt5 2>/dev/null || true
fi
ok "Kvantum ready"

# ── 5. SelahBridge scripts ───────────────────────────────────
step "Installing SelahBridge tools..."
for script in selahbridge-setup selahbridge-init selahbridge-uninstaller selahos-installer; do
    src="$AIROOTFS/usr/local/bin/$script"
    if [ -f "$src" ]; then
        cp "$src" "/usr/local/bin/$script"
        chmod +x "/usr/local/bin/$script"
        echo -e "    ${DIM}✓ $script${NC}"
    fi
done
ok "SelahBridge tools installed"

# ── 6. System configs ─────────────────────────────────────────
step "Applying system configs..."

# NTSYNC
echo "ntsync" > /etc/modules-load.d/ntsync.conf

# WiFi powersave fix
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF

cat > /etc/udev/rules.d/70-wifi-powersave.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/sbin/iwconfig %k power off"
EOF

# Realtime limits
if ! grep -q "@realtime" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'
@realtime   -  rtprio     99
@realtime   -  memlock    unlimited
@audio      -  rtprio     99
@audio      -  memlock    unlimited
EOF
fi

# PipeWire JACK
mkdir -p "$REAL_HOME/.config/pipewire"
cat > "$REAL_HOME/.config/pipewire/jack.conf" << 'EOF'
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 256
    default.clock.min-quantum = 64
    default.clock.max-quantum = 8192
}
EOF
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/pipewire"

# GRUB branding
sed -i 's/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="SelahOS"/' \
    /etc/default/grub 2>/dev/null || true
ok "System configs applied"

# ── 7. Install missing packages ──────────────────────────────
step "Installing any missing packages..."
pacman -S --noconfirm --needed \
    kvantum kvantum-qt5 \
    realtime-privileges \
    python-pyqt6 \
    pipewire-jack \
    lib32-pipewire-jack \
    lib32-gstreamer \
    lib32-alsa-plugins 2>/dev/null || true
ok "Packages checked"

# ── 8. Groups ────────────────────────────────────────────────
step "Ensuring correct group membership..."
usermod -aG audio,realtime,input,storage,wheel "$REAL_USER" 2>/dev/null || true
ok "Groups updated"

# ── 9. Swap (zram + disk swapfile) ───────────────────────────
step "Configuring swap..."
cp "$AIROOTFS/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
systemctl enable --now systemd-zram-setup@zram0.service 2>/dev/null || true
ok "zram swap enabled (4 GiB, lz4)"

if [ ! -f /swapfile ]; then
    fallocate -l 16G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    ok "16 GiB swapfile created at /swapfile"
else
    ok "swapfile already exists, skipping"
fi
if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap defaults,pri=10 0 0' >> /etc/fstab
    ok "swapfile added to /etc/fstab"
fi
swapon /swapfile -p 10 2>/dev/null || true
ok "Swap: zram (priority 100) + 16 GiB disk (priority 10)"

# ── 10. Rebuild GRUB ─────────────────────────────────────────
step "Rebuilding GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
ok "GRUB rebuilt"

# ── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GOLD}  ══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ SelahOS restore complete${NC}"
echo -e "${GOLD}  ══════════════════════════════════════════${NC}"
echo ""
echo -e "${DIM}  To apply the KDE theme visually:${NC}"
echo -e "${DIM}  1. Open System Settings → Appearance → Colors → Selah${NC}"
echo -e "${DIM}  2. System Settings → Application Style → Kvantum → Selah${NC}"
echo -e "${DIM}  OR log out and back in — it applies automatically${NC}"
echo ""
echo -e "  ${GOLD}Pause. Reflect. Create.${NC}"
echo ""
