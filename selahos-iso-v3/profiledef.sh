#!/usr/bin/env bash
# shellcheck disable=SC2034
# SelahOS v1.0-beta archiso profile
# Copyright (C) 2026 Selah Technologies LLC

iso_name="selahos"
iso_label="SELAHOS_$(date +%Y%m)"
iso_publisher="Selah Technologies LLC <https://selahos.io>"
iso_application="SelahOS Beta — Live and Install Medium"
iso_version="1.0.0-beta-$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux'
  'uefi.grub'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/etc/sudoers.d/liveuser"]="0:0:440"
  ["/etc/mkinitcpio.conf"]="0:0:644"
  ["/etc/mkinitcpio.d/linux-zen.preset"]="0:0:644"
  ["/etc/mkinitcpio.d/linux-lts.preset"]="0:0:644"
  ["/usr/local/bin/selah-rescue"]="0:0:755"
  ["/usr/local/bin/selah-update"]="0:0:755"
  ["/usr/local/bin/selah-ai-detect"]="0:0:755"
  ["/usr/local/bin/selah-ai-setup"]="0:0:755"
  ["/usr/local/bin/selahos-welcome"]="0:0:755"
  ["/usr/local/bin/selahos-firstrun-notice"]="0:0:755"
  ["/usr/local/bin/selahos-calamares-launcher"]="0:0:755"
  ["/usr/local/bin/selahos-memory-info"]="0:0:755"
  ["/usr/local/bin/selahos-hardware-detect"]="0:0:755"
  ["/usr/local/bin/selahos-installer"]="0:0:755"
  ["/usr/local/bin/selahos-installer-launcher"]="0:0:755"
  ["/usr/local/bin/selahbridge-setup"]="0:0:755"
  ["/usr/local/bin/selahbridge-init"]="0:0:755"
  ["/usr/local/bin/selahbridge-uninstaller"]="0:0:755"
  ["/usr/local/bin/selah-recover"]="0:0:755"
  ["/usr/local/bin/selahos-recovery-center"]="0:0:755"
  ["/usr/local/bin/selahbridge-manager"]="0:0:755"
)
