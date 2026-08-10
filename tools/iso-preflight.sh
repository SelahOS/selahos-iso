#!/usr/bin/env bash
# ============================================================
# iso-preflight.sh — verify a built SelahOS ISO before flashing
#
# Usage: sudo bash iso-preflight.sh [path-to-iso]
#        (defaults to newest ISO in ~/selahos-iso-output)
#
# Checks, inside the ISO's airootfs squashfs:
#   1. every /usr/local/bin/selah* is executable   (SELAH-40)
#   2. device editor suite is present + launcher executable
#   3. Broadcom config is the per-chip design: all drivers
#      blacklisted, nothing force-loaded, selah-wifi-driver
#      service present and enabled
#   4. NetworkManager enabled
#   5. theme/fastfetch payload present
#   6. SELAH-49 sleep/clamshell: selah-clamshell + acpid event present,
#      logind.conf lid directives correct, installer propagates all of
#      it (+ pacstraps acpid) to installed systems
# ============================================================
set -uo pipefail

ISO="${1:-$(ls -t /home/dbnoble/selahos-iso-output/*.iso 2>/dev/null | head -1)}"
[ -f "$ISO" ] || { echo "FAIL: no ISO found"; exit 1; }
echo "Pre-flight: $ISO"

MNT=$(mktemp -d)
SFS=$(mktemp -d)
cleanup() { umount "$SFS" 2>/dev/null; umount "$MNT" 2>/dev/null; rmdir "$SFS" "$MNT" 2>/dev/null; }
trap cleanup EXIT

mount -o loop,ro "$ISO" "$MNT" || { echo "FAIL: cannot mount ISO"; exit 1; }
mount -o loop,ro "$MNT"/arch/x86_64/airootfs.sfs "$SFS" || { echo "FAIL: cannot mount airootfs.sfs"; exit 1; }

fail=0
ok()   { echo "  OK   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }

# 1. exec bits on selah tools
for f in "$SFS"/usr/local/bin/selah*; do
    [ -f "$f" ] || continue
    [ -x "$f" ] && ok "exec: ${f#"$SFS"}" || bad "NOT executable: ${f#"$SFS"}"
done

# 1b. no editor-backup/junk files (selah-setup's cp glob would ship them to installs)
junk=$(find "$SFS/usr/local/bin" "$SFS/usr/local/lib/selahos" \
            -name '*.bak' -o -name '*.orig' -o -name '*~' \
            -o -name '__pycache__' -o -name '*.pyc' 2>/dev/null)
[ -z "$junk" ] && ok "no junk files in /usr/local" \
    || bad "junk files present: $(echo "$junk" | sed "s|$SFS||" | tr '\n' ' ')"

# 2. device editor suite
DB="$SFS/usr/local/lib/selahos/device-bridge"
for f in selahos-device-editors mpc_studio2_editor.py apc_mini_editor.py \
         lpd8_mk2_editor.py lpd8_mk3_editor.py mpd226_editor.py \
         mpk261_editor.py selahos-central-dashboard.py; do
    [ -f "$DB/$f" ] && ok "editor: $f" || bad "missing editor: $f"
done
[ -x "$DB/selahos-device-editors" ] && ok "launcher executable" || bad "launcher not executable"
n=$(ls "$SFS"/usr/share/applications/selah-*editor*.desktop "$SFS"/usr/share/applications/selah-device-*.desktop 2>/dev/null | wc -l)
[ "$n" -ge 8 ] && ok "desktop entries: $n" || bad "only $n editor desktop entries"

# 3. Broadcom per-chip design
grep -qs "blacklist brcmfmac" "$SFS/etc/modprobe.d/selah-broadcom.conf" \
    && ok "brcmfmac blacklisted (per-chip selection)" || bad "brcmfmac not blacklisted"
grep -qs "blacklist wl" "$SFS/etc/modprobe.d/selah-broadcom.conf" \
    && ok "wl blacklisted (per-chip selection)" || bad "wl not blacklisted"
if grep -hsvE '^\s*(#|$)' "$SFS"/etc/modules-load.d/*wifi*.conf "$SFS"/etc/modules-load.d/*broadcom*.conf 2>/dev/null | grep -q .; then
    bad "a Wi-Fi driver is force-loaded in modules-load.d (bypasses blacklist)"
else
    ok "no Wi-Fi driver force-loaded"
fi
[ -f "$SFS/etc/systemd/system/selah-wifi-driver.service" ] \
    && ok "selah-wifi-driver.service present" || bad "selah-wifi-driver.service missing"
[ -L "$SFS/etc/systemd/system/multi-user.target.wants/selah-wifi-driver.service" ] \
    && ok "selah-wifi-driver enabled" || bad "selah-wifi-driver not enabled"
[ -x "$SFS/usr/local/bin/selah-wifi-driver" ] \
    && ok "selah-wifi-driver script executable" || bad "selah-wifi-driver script missing/not exec"
grep -qs "'broadcom-wl-dkms'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps broadcom-wl-dkms (wl chips on installs)" \
    || bad "installer missing broadcom-wl-dkms — installed wl-class Macs get no Wi-Fi"

# 4. NetworkManager
[ -L "$SFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ] \
    && ok "NetworkManager enabled" || bad "NetworkManager not enabled"

# 5. theme + fastfetch payload (what _apply_theme copies to installs)
for d in usr/share/Kvantum/Selah usr/share/sddm/themes/selahos \
         usr/share/wallpapers/selahos etc/xdg/fastfetch \
         etc/skel/.config/fastfetch; do
    [ -d "$SFS/$d" ] && ok "theme: /$d" || bad "theme payload missing: /$d"
done
[ -f "$SFS/etc/profile.d/50-selahos-fastfetch.sh" ] \
    && ok "fastfetch profile.d snippet" || bad "fastfetch profile.d snippet missing"
grep -qs "'kvantum'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps kvantum/fastfetch" || bad "installer missing kvantum/fastfetch pacstrap"
[ -x "$SFS/usr/local/bin/selah-repair" ] \
    && ok "selah-repair present + executable" || bad "selah-repair missing or not executable"

# 6. SELAH-49 sleep/clamshell handling
[ -x "$SFS/usr/local/bin/selah-clamshell" ] \
    && ok "selah-clamshell present + executable" || bad "selah-clamshell missing or not executable"
[ -f "$SFS/etc/acpi/events/selah-lid" ] \
    && ok "selah-lid acpid event present" || bad "selah-lid acpid event missing"
grep -qs "HandleLidSwitchExternalPower=ignore" "$SFS/etc/systemd/logind.conf" \
    && ok "logind.conf: lid-on-AC handed to selah-clamshell" \
    || bad "logind.conf HandleLidSwitchExternalPower not set to ignore"
grep -qs "^HandleLidSwitch=suspend" "$SFS/etc/systemd/logind.conf" \
    && ok "logind.conf: plain lid-close-to-suspend still set" \
    || bad "logind.conf HandleLidSwitch not set to suspend — lid-close-to-suspend would break"

# 7. bake-fixes handoff (2026-07-27): re-verify SELAH-36 didn't regress,
# and that the new fixes actually landed in this build
grep -qs "^GRUB_CMDLINE_LINUX_DEFAULT=" "$SFS/etc/default/grub" && \
    grep -qs '"[^"]*\(quiet\|splash\)[^"]*"' "$SFS/etc/default/grub" \
        && { grep -qs "plymouth" "$SFS/etc/mkinitcpio.conf" \
                && ok "quiet/splash present with matching plymouth hook" \
                || bad "quiet/splash set in grub but no plymouth hook in mkinitcpio.conf (SELAH-36 regression)"; } \
        || ok "no quiet/splash in default grub cmdline"
for f in usr/local/bin/selah-preflight-check; do
    [ -x "$SFS/$f" ] && ok "$f present + executable" || bad "$f missing or not executable"
done
grep -qs "'/usr/local/bin/selah-preflight-check'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer runs selah-preflight-check before final reboot prompt" \
    || bad "installer never runs selah-preflight-check — Task 3 not wired in"
grep -qs '"preflight"' "$SFS/usr/local/bin/selahpro" \
    && ok "selahpro preflight subcommand present" \
    || bad "selahpro has no preflight subcommand"
[ -f "$SFS/etc/pacman.conf" ] \
    && ok "airootfs pacman.conf override present (not the build-machine one)" \
    || bad "no airootfs/etc/pacman.conf override — ISO would ship the build machine's file:// local-repo path"
grep -qs "selahos" "$SFS/etc/pacman.conf" 2>/dev/null \
    && ok "pacman.conf: [selahos] repo section present (even if disabled)" \
    || bad "pacman.conf has no [selahos] repo section at all"
grep -qs "xf86-video-nouveau" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps xf86-video-nouveau (non-Mac NVIDIA default)" \
    || bad "installer missing xf86-video-nouveau pacstrap"
grep -qs "'/etc/systemd/logind.conf'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies logind.conf to installed systems" \
    || bad "installer never copies logind.conf — installed Macs get systemd defaults (unset lid handling)"
grep -qs "'/usr/local/bin/selah-clamshell'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies selah-clamshell to installed systems" \
    || bad "installer never copies selah-clamshell"
grep -qs "'acpid'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps acpid (selah-clamshell needs it running)" \
    || bad "installer missing acpid pacstrap — selah-clamshell will never fire on installed systems"

# 8. SELAH-50 addendum: preflight's PCI/USB hardware scan needs lspci/lsusb
# on the INSTALLED system, not just the live ISO
grep -qs "'pciutils'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps pciutils (preflight's PCI scan needs lspci)" \
    || bad "installer missing pciutils pacstrap — selah-preflight-check's hardware scan would silently no-op post-install"
grep -qs "'usbutils'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps usbutils (preflight's Bluetooth check needs lsusb)" \
    || bad "installer missing usbutils pacstrap"

# 9. CS8409 audio (MacBook Pro 14,1): confirm the dkms module actually
# compiled during THIS build, not just that the package is "installed" —
# its build needs network, which pacstrap's own hook execution doesn't
# have (see customize_airootfs.sh and packages.x86_64 comments). A
# compiled module for at least one of the two shipped kernels means the
# fix (installing via customize_airootfs.sh instead of packages.x86_64)
# is working; zero anywhere means it silently regressed again.
# NOTE: don't just search for snd-hda-codec-cs8409.ko anywhere under
# /usr/lib/modules — the STOCK in-tree kernel already ships a module by
# that exact name (generic CS8409 support, not the Apple-patched one),
# so that alone is a false positive. Check the dkms build log itself.
# NOTE: the on-disk dkms tree is keyed by the /usr/src/<name> directory
# name — "snd-hda-macbookpro" (hyphen) — NOT dkms.conf's internal
# PACKAGE_NAME ("snd_hda_macbookpro", underscore). Got this wrong on the
# first pass here and it produced a false FAIL against a build that had
# actually succeeded (dkms had already promoted the log from the
# in-progress build/make.log path to the final <kernelver>/<arch>/log/
# path, which only happens on success — checked both possible locations
# by searching the whole module tree rather than guessing one path).
DKMS_LOGS="$(find "$SFS/var/lib/dkms/snd-hda-macbookpro" -iname "make.log" 2>/dev/null)"
if [ -z "$DKMS_LOGS" ]; then
    bad "CS8409 driver: no dkms build was ever attempted in this ISO — check customize_airootfs.sh's pacman -U snd-hda-macbookpro-dkms-git*.pkg.tar.zst step ran"
elif echo "$DKMS_LOGS" | xargs grep -lE "^Error|exit code: [^0]" 2>/dev/null | grep -q .; then
    bad_log="$(echo "$DKMS_LOGS" | xargs grep -lE '^Error|exit code: [^0]' 2>/dev/null | head -1)"
    bad "CS8409 driver: dkms build attempted but failed — see $(echo "$bad_log" | sed "s|$SFS||")"
else
    ok "CS8409 driver (snd_hda_macbookpro) dkms-built successfully for at least one kernel"
fi

# 10. bake-fixes handoff Task 6: Discover has no app backend without
# flatpak installed AND a Flathub remote configured on the INSTALLED
# system (live-ISO packages.x86_64 having flatpak isn't enough).
grep -qs "'flatpak'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer pacstraps flatpak" \
    || bad "installer never pacstraps flatpak — Discover has no app backend on installs"
grep -qs "flatpak.*remote-add" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer adds the flathub remote" \
    || bad "installer never adds a flathub remote — Discover shows the 'not configured' prompt Task 6 reported"
grep -qs "flathub" "$SFS/usr/local/bin/selah-repair" \
    && ok "selah-repair can add flathub remote (already-flashed systems)" \
    || bad "selah-repair has no flathub remote fallback"

# 11. selah-postflight-check: live-system hardware health tool ships,
# its pacman dependencies (bluez/bluez-utils for Bluetooth, smartmontools
# for disk health, iw for live WiFi power-save state) are pacstrapped by
# the installer, and it has an app-menu launcher.
[ -x "$SFS/usr/local/bin/selah-postflight-check" ] \
    && ok "selah-postflight-check present + executable" \
    || bad "selah-postflight-check missing or not executable"
for pkg in bluez bluez-utils smartmontools iw; do
    grep -qs "'$pkg'" "$SFS/usr/local/bin/selah-setup" \
        && ok "installer pacstraps $pkg" \
        || bad "installer never pacstraps $pkg — selah-postflight-check dependency missing on installs"
done
[ -f "$SFS/usr/share/applications/selah-postflight-check.desktop" ] \
    && ok "selah-postflight-check has an app-menu launcher" \
    || bad "selah-postflight-check has no .desktop launcher"

echo
if [ "$fail" -eq 0 ]; then
    echo "PRE-FLIGHT PASSED — safe to flash"
else
    echo "PRE-FLIGHT FAILED — do not flash this ISO"
fi
exit "$fail"
