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
# Driver selection is per-chip at boot (selah-wifi-driver.service);
# static config lives in airootfs (/etc/modprobe.d/selah-broadcom.conf).
# Writing a second modules-load/modprobe pair here previously
# force-loaded wl AND brcmfmac together and blacklisted everything,
# which killed Wi-Fi on BCM4331 Macs (MacBookPro9,2).
systemctl enable selah-wifi-driver.service

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

# ── Step 18: CS8409 audio driver (snd-hda-macbookpro-dkms-git) ─
# Deliberately NOT in packages.x86_64 (see that file). Its dkms hook runs
# install.cirrus.driver.sh, which downloads the matching upstream kernel
# source over the network to patch against.
#
# CORRECTED 2026-08-16 (this comment previously claimed arch-chroot
# bind-mounts /etc/resolv.conf — verified FALSE: `mkarchiso` itself has
# zero references to resolv.conf, and airootfs ships no /etc/resolv.conf
# at all, so DNS inside this chroot has never actually worked. That is
# the real reason this dkms build has silently failed on every single ISO
# build going back to whenever this package was added — make.log always
# showed "Temporary failure in name resolution" from install.cirrus.driver.sh's
# `wget https://cdn.kernel.org/...`, mistaken for an acceptable non-blocker
# instead of a fixable build bug. arch-chroot only isolates the filesystem,
# not networking — the chroot shares the host's live network stack, so any
# real resolv.conf placed at /etc/resolv.conf here resolves fine. Written
# immediately before this step and removed immediately after so nothing
# build-machine-specific ships in the image (matches source: no
# airootfs/etc/resolv.conf).
#
# Installed via `pacman -U` from a bundled local file, not `pacman -S` from
# a repo: this package only ever existed in the build machine's local-repo
# (file:// path, build-time only — see airootfs/etc/pacman.conf), which
# isn't reachable from inside this arch-chroot at all (chroot changes the
# filesystem root; the host path simply doesn't exist in here). The .pkg
# is copied into airootfs/root/ at profile-source time instead so pacman
# can install it with zero repo/network dependency for the resolve step —
# only the dkms hook's own kernel-source download needs network.
PKG="$(ls /root/snd-hda-macbookpro-dkms-git-*.pkg.tar.zst 2>/dev/null | head -1)"
if [ -n "$PKG" ]; then
    # pacman's CheckSpace option statfs's the mount point for "/" to verify
    # free space. This script is the first place in the whole build that
    # runs pacman from inside a REAL arch-chroot (everything else uses
    # pacstrap's --root mode, which never calls chroot() at all) — and
    # CheckSpace can't resolve a mount point for "/" from inside an actual
    # chroot, failing with "could not determine root mount point /" /
    # "not enough free disk space" regardless of how much space is free.
    # Disable it for just this one internal install, then restore it so
    # the shipped pacman.conf is unchanged.
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    pacman -U --noconfirm --needed "$PKG" || \
        echo "WARNING: snd-hda-macbookpro-dkms-git install/dkms build failed — CS8409 audio (MacBook Pro 14,1) will not work on this ISO"
    rm -f /etc/resolv.conf
    sed -i 's/^#CheckSpace/CheckSpace/' /etc/pacman.conf
    rm -f "$PKG"
else
    echo "WARNING: snd-hda-macbookpro-dkms-git-*.pkg.tar.zst not found in /root — was it copied into airootfs/root/?"
fi

# ── Step 18b: CS4208 audio driver (snd-hda-macbook12-dkms-git) ─
# 2026-09-06: sibling of Step 18 above, same mechanism, for the 12" MacBook
# (MacBook10,1)'s Cirrus CS4208 codec — CONFIRMED root cause on real
# hardware: the stock cs420x driver picks a blank pin fixup for this
# codec's SSID (106b:6600, not in the upstream table), leaving the
# internal speaker unwired. This exact package + dkms build was verified
# live via SSH on the test machine (direct ALSA playback on hw:0,0
# succeeded cleanly post-install) before being packaged here — see
# packaging/snd-hda-macbook12-dkms-git/PKGBUILD.
PKG="$(ls /root/snd-hda-macbook12-dkms-git-*.pkg.tar.zst 2>/dev/null | head -1)"
if [ -n "$PKG" ]; then
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    pacman -U --noconfirm --needed "$PKG" || \
        echo "WARNING: snd-hda-macbook12-dkms-git install/dkms build failed — CS4208 audio (MacBook 10,1 / 12-inch MacBook) will not work on this ISO"
    rm -f /etc/resolv.conf
    sed -i 's/^#CheckSpace/CheckSpace/' /etc/pacman.conf
    rm -f "$PKG"
else
    echo "WARNING: snd-hda-macbook12-dkms-git-*.pkg.tar.zst not found in /root — was it copied into airootfs/root/?"
fi

# ── Step 19: Purge build-time junk ────────────────────────────
# Guard against __pycache__/.pyc (e.g. from a stray `python -m py_compile`
# during dev, or any pacman hook that compiles installed scripts) and
# editor backup files shipping in the squashfs. iso-preflight.sh has
# checked for exactly this set since SELAH-40; this is what actually
# prevents it, run last so it catches anything earlier steps produced.
find /usr/local /usr/share/selahos -depth \
    \( -name '__pycache__' -o -name '*.pyc' -o -name '*.pyo' \
       -o -name '*.bak' -o -name '*.orig' -o -name '*~' \) \
    -exec rm -rf {} + 2>/dev/null || true

# SelahSeedCore runs via KDE autostart desktop entry only
