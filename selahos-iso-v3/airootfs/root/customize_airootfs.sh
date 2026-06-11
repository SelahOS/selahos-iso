#!/usr/bin/env bash
# ============================================================
# SelahOS v1.0-beta — customize_airootfs.sh
# Definitive version — all Omolara findings addressed
# Copyright (C) 2026 Selah Technologies LLC
# ============================================================

set -uo pipefail

# ── Step 1: Create ALL groups before any useradd ─────────────
# Note: do NOT pre-create 'liveuser' group — useradd needs to own it
groupadd -r autologin  2>/dev/null || true
groupadd -r bluetooth  2>/dev/null || true
groupadd -r realtime   2>/dev/null || true
groupadd    storage    2>/dev/null || true
groupadd    optical    2>/dev/null || true
groupadd    network    2>/dev/null || true
groupadd    input      2>/dev/null || true

# ── Step 2: Create liveuser (safe group list only) ───────────
useradd -m \
    -G wheel,audio,video,storage,optical,network,input,autologin \
    -s /bin/bash \
    liveuser

# Add optional groups separately (won't fail if group missing)
for grp in bluetooth realtime sys lp; do
    usermod -aG "$grp" liveuser 2>/dev/null || true
done

echo "liveuser:liveuser" | chpasswd
passwd -d liveuser
passwd -d root

# Passwordless sudo for live session
echo "liveuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/liveuser
chmod 440 /etc/sudoers.d/liveuser

# Wheel sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/'         /etc/sudoers

# Copy skel
cp -r /etc/skel/. /home/liveuser/
chown -R liveuser:liveuser /home/liveuser

# Desktop shortcut
mkdir -p /home/liveuser/Desktop
cp /usr/share/applications/selahos-install.desktop \
   /home/liveuser/Desktop/ 2>/dev/null || true
chmod +x /home/liveuser/Desktop/selahos-install.desktop 2>/dev/null || true
chown -R liveuser:liveuser /home/liveuser/Desktop

# ── Step 3: Locale + Timezone ────────────────────────────────
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
# Set UTC so systemd-firstboot never prompts for timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Block plasma-welcome wizard (also overridden via /etc/xdg/autostart/,
# but belt-and-suspenders: remove the package's own autostart entry)
mkdir -p /etc/xdg/autostart
for f in plasma-welcome plasma-initial-setup kde-firstrun; do
    if [ -f "/etc/xdg/autostart/${f}.desktop" ]; then
        # Override rather than delete so package updates can't re-add it
        echo '[Desktop Entry]' > "/etc/xdg/autostart/${f}.desktop"
        echo 'Hidden=true'   >> "/etc/xdg/autostart/${f}.desktop"
    fi
done

# ── Step 4: Services ──────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sddm
systemctl enable bolt    2>/dev/null || true
systemctl enable acpid   2>/dev/null || true
systemctl enable dhcpcd  2>/dev/null || true

# ── Step 5: Keyring (pre-initialized) ────────────────────────
pacman-key --init
pacman-key --populate archlinux
echo "✓ Keyring initialized"

# ── Step 6: zram ─────────────────────────────────────────────
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# ── Step 7: Creator sysctl ────────────────────────────────────
cat > /etc/sysctl.d/99-selahos-creator.conf << 'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
fs.inotify.max_user_watches = 524288
EOF

# ── Step 8: NTSYNC ────────────────────────────────────────────
echo "ntsync" > /etc/modules-load.d/ntsync.conf

# ── Step 9: Broadcom WiFi ─────────────────────────────────────
echo "wl" > /etc/modules-load.d/broadcom-wl.conf
cat > /etc/modprobe.d/broadcom-wl.conf << 'EOF'
blacklist b43
blacklist b43legacy
blacklist ssb
blacklist bcma
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
EOF

# ── Step 10: WiFi powersave fix ───────────────────────────────
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 2
EOF
cat > /etc/udev/rules.d/70-wifi-powersave.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/sbin/iwconfig %k power off"
EOF

# ── Step 11: Realtime audio ───────────────────────────────────
cat >> /etc/security/limits.conf << 'EOF'
@realtime   -  rtprio     99
@realtime   -  memlock    unlimited
@audio      -  rtprio     99
@audio      -  memlock    unlimited
EOF

# ── Step 12: PipeWire JACK ────────────────────────────────────
mkdir -p /etc/pipewire
cat > /etc/pipewire/jack.conf << 'EOF'
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 256
    default.clock.min-quantum = 64
    default.clock.max-quantum = 8192
}
EOF

# ── Step 13: GRUB branding ────────────────────────────────────
[ -f /etc/default/grub ] && \
    sed -i 's/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="SelahOS"/' /etc/default/grub

# ── Step 14: SDDM theme ───────────────────────────────────────
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-selah-theme.conf << 'EOF'
[Theme]
Current=selahos
EOF

# SDDM autologin for live environment
cat > /etc/sddm.conf.d/autologin.conf << 'EOF'
[Autologin]
User=liveuser
Session=plasmawayland
Relogin=false
EOF

# ── Step 15: WineASIO fix (Omolara finding) ───────────────────
# Create helper script that uses correct registration method
cat > /usr/local/bin/selahbridge-register-asio << 'EOF'
#!/usr/bin/env bash
# Register WineASIO correctly for both 32 and 64 bit
if command -v wineasio-register &>/dev/null; then
    wineasio-register
else
    wine regsvr32 wineasio.dll 2>/dev/null || true
    wine64 regsvr32 wineasio64.dll 2>/dev/null || true
fi
echo "✓ WineASIO registered"
EOF
chmod +x /usr/local/bin/selahbridge-register-asio

# ── Step 16: FireWire ─────────────────────────────────────────
cat > /etc/modules-load.d/selahos-firewire.conf << 'EOF'
firewire-core
firewire-ohci
EOF

# ── Step 17: Plymouth ────────────────────────────────────────
command -v plymouth-set-default-theme &>/dev/null && \
    plymouth-set-default-theme selahos 2>/dev/null || \
    plymouth-set-default-theme spinner  2>/dev/null || true

# Ensure plymouth hook is present for the installed system's initramfs.
# The live ISO uses archiso hooks (no plymouth); the installed system needs it.
if [ -f /etc/mkinitcpio.conf ]; then
    if ! grep -q 'plymouth' /etc/mkinitcpio.conf; then
        sed -i 's/\budev\b/udev plymouth/' /etc/mkinitcpio.conf
    fi
fi

echo "customize_airootfs.sh complete — SelahOS v1.0-beta"

# SelahSeedCore — only enable on Apple hardware
if dmidecode -s system-manufacturer 2>/dev/null | grep -qi "apple"; then
    systemctl enable bluetooth
    echo "SelahSeedCore: Apple hardware detected — services enabled"
else
    echo "SelahSeedCore: Non-Apple hardware — skipping Mac-specific services"
fi

# SelahSeedCore runs via KDE autostart desktop entry only
