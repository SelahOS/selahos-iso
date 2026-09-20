#!/usr/bin/env bash
# ============================================================
# iso-preflight.sh — verify a built SelahOS ISO before flashing
#
# Usage: sudo bash iso-preflight.sh [path-to-iso]
#        (defaults to newest ISO in the invoking user's ~/selahos-iso-output)
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

_home="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
ISO="${1:-$(ls -t "${_home:-$HOME}"/selahos-iso-output/*.iso 2>/dev/null | head -1)}"
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
# 2026-09-04: package lists moved out of selah-setup's literal source into
# usr/local/share/selahos-install-packages/*.txt (shared source of truth
# with tools/build-offline-repo.sh) — checks below grep those files
# instead of selah-setup itself now.
PKGLISTS="$SFS/usr/local/share/selahos-install-packages"
grep -qsx "broadcom-wl-dkms" "$PKGLISTS/base.txt" \
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
grep -qsx "kvantum" "$PKGLISTS/kde.txt" \
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

# 7b. 2026-09-04: offline install repo — the actual fix for "installer
# needs internet for a fresh install." Must exist ahead of network repos,
# and jack2 must be genuinely absent from it (not just unrequested) so the
# pipewire-jack/jack2 conflict that crashed a real install is structurally
# impossible, not just avoided by omission.
offline_line="$(awk '/^\[selahos-offline\]/{print NR; exit}' "$SFS/etc/pacman.conf" 2>/dev/null)"
core_line="$(awk '/^\[core\]/{print NR; exit}' "$SFS/etc/pacman.conf" 2>/dev/null)"
if [ -n "$offline_line" ] && [ -n "$core_line" ] && [ "$offline_line" -lt "$core_line" ]; then
    ok "pacman.conf: [selahos-offline] present and ordered ahead of [core]"
else
    bad "pacman.conf: [selahos-offline] missing or not ahead of network repos — installs would still hit the network first"
fi
grep -qs "^IgnorePkg.*jack2" "$SFS/etc/pacman.conf" \
    && ok "pacman.conf: IgnorePkg = jack2 present" \
    || bad "pacman.conf missing IgnorePkg = jack2 — pipewire-jack conflict could recur"
OFFLINE_REPO="$SFS/usr/local/share/selahos-offline-repo"
[ -f "$OFFLINE_REPO/selahos-offline.db" ] || [ -f "$OFFLINE_REPO/selahos-offline.db.tar.gz" ] \
    && ok "offline repo database present in the ISO" \
    || bad "offline repo database missing from the ISO — selahos-offline-repo/ has no repo-add DB"
find "$OFFLINE_REPO" -iname "jack2-*.pkg.tar.*" 2>/dev/null | grep -q . \
    && bad "jack2 package file found IN the bundled offline repo — conflict will recur despite IgnorePkg" \
    || ok "jack2 genuinely absent from the bundled offline repo"
grep -qs "sh(\['pacman', '-Sy'\])" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer syncs pacman dbs (incl. selahos-offline) before pacstrapping — confirmed necessary 2026-09-04, bundling repo files alone isn't enough" \
    || bad "installer never runs pacman -Sy — selahos-offline repo's database won't be recognized, pacstrap will need network for everything despite the bundle"
for f in base base-apple-extra kde audio wine; do
    [ -f "$PKGLISTS/$f.txt" ] && ok "install package list present: $f.txt" \
        || bad "install package list missing: $f.txt"
done
grep -qs "base_pkgs = load_pkglist" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer reads package lists from files (not hardcoded literals)" \
    || bad "installer still hardcodes package lists — offline repo and installer requests can drift apart again"

grep -qsx "xf86-video-nouveau" "$PKGLISTS/kde.txt" \
    && ok "installer pacstraps xf86-video-nouveau (non-Mac NVIDIA default)" \
    || bad "installer missing xf86-video-nouveau pacstrap"
grep -qs "'/etc/systemd/logind.conf'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies logind.conf to installed systems" \
    || bad "installer never copies logind.conf — installed Macs get systemd defaults (unset lid handling)"
grep -qs "'/usr/local/bin/selah-clamshell'" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies selah-clamshell to installed systems" \
    || bad "installer never copies selah-clamshell"
grep -qsx "acpid" "$PKGLISTS/base-apple-extra.txt" \
    && ok "installer pacstraps acpid (selah-clamshell needs it running)" \
    || bad "installer missing acpid pacstrap — selah-clamshell will never fire on installed systems"

# 8. SELAH-50 addendum: preflight's PCI/USB hardware scan needs lspci/lsusb
# on the INSTALLED system, not just the live ISO
grep -qsx "pciutils" "$PKGLISTS/base.txt" \
    && ok "installer pacstraps pciutils (preflight's PCI scan needs lspci)" \
    || bad "installer missing pciutils pacstrap — selah-preflight-check's hardware scan would silently no-op post-install"
grep -qsx "usbutils" "$PKGLISTS/base.txt" \
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

# 9b. CS4208 audio (MacBook10,1 / 12" MacBook) — sibling check to #9 above,
# same reasoning: confirm the dkms module actually compiled during THIS
# build. On-disk dkms tree is keyed by /usr/src/macbook12-audio (dkms.conf's
# PACKAGE_NAME is "macbook12-audio-driver", directory is "macbook12-audio"
# — same naming mismatch trap as the CS8409 check, checked directly here).
DKMS_LOGS_CS4208="$(find "$SFS/var/lib/dkms/macbook12-audio" -iname "make.log" 2>/dev/null)"
if [ -z "$DKMS_LOGS_CS4208" ]; then
    bad "CS4208 driver: no dkms build was ever attempted in this ISO — check customize_airootfs.sh's pacman -U snd-hda-macbook12-dkms-git*.pkg.tar.zst step ran"
elif echo "$DKMS_LOGS_CS4208" | xargs grep -lE "^Error|exit code: [^0]" 2>/dev/null | grep -q .; then
    bad_log_cs4208="$(echo "$DKMS_LOGS_CS4208" | xargs grep -lE '^Error|exit code: [^0]' 2>/dev/null | head -1)"
    bad "CS4208 driver: dkms build attempted but failed — see $(echo "$bad_log_cs4208" | sed "s|$SFS||")"
else
    ok "CS4208 driver (macbook12-audio) dkms-built successfully for at least one kernel"
fi

# 10. bake-fixes handoff Task 6: Discover has no app backend without
# flatpak installed AND a Flathub remote configured on the INSTALLED
# system (live-ISO packages.x86_64 having flatpak isn't enough).
grep -qsx "flatpak" "$PKGLISTS/kde.txt" \
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
    grep -qsx "$pkg" "$PKGLISTS/base.txt" \
        && ok "installer pacstraps $pkg" \
        || bad "installer never pacstraps $pkg — selah-postflight-check dependency missing on installs"
done
[ -f "$SFS/usr/share/applications/selah-postflight-check.desktop" ] \
    && ok "selah-postflight-check has an app-menu launcher" \
    || bad "selah-postflight-check has no .desktop launcher"

# 12. Bootloader-not-installed bug: grub-install used to be logged as a
# WARNING and never verified, so a failed install still reached "SelahOS
# is installed" with no EFI boot files. selah-doctor verifies + repairs
# this; selah-setup must actually wire it in and must NOT unmount /mnt
# before the user has a chance to repair.
[ -x "$SFS/usr/local/bin/selah-doctor" ] \
    && ok "selah-doctor present + executable" \
    || bad "selah-doctor missing or not executable"
grep -qs "_bootloader_installed" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer verifies grub-install actually wrote EFI boot files" \
    || bad "installer never verifies the bootloader — silent grub-install failures possible"
grep -qs "selah-doctor" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer's Done screen can invoke selah-doctor to repair before reboot" \
    || bad "installer has no repair-before-reboot path wired to selah-doctor"
# The one legitimate `sh(['umount', '-R', '/mnt'])` is the PRE-install stale-state
# cleanup (2026-09-12, e88a6e0), which always sits right after the gpg-agent
# pkill. Any other occurrence would be a post-install unmount. (This check used
# to reject the literal anywhere, which false-failed once that cleanup landed.)
_SETUP="$SFS/usr/local/bin/selah-setup"
_umounts=$(grep -c "sh(\['umount', '-R', '/mnt'\])" "$_SETUP" 2>/dev/null)
_precleanups=$(grep -B1 "sh(\['umount', '-R', '/mnt'\])" "$_SETUP" 2>/dev/null | grep -c "pkill.*gpg-agent.*--homedir /mnt")
grep -qs "def _do_restart" "$_SETUP" \
    && [ "${_umounts:-0}" -eq "${_precleanups:-0}" ] \
    && ok "/mnt stays mounted until the Done screen's restart action" \
    || bad "installer still unmounts /mnt right after install — Repair Now would have nothing to act on"
[ -f "$SFS/etc/polkit-1/rules.d/49-selahos-liveuser-nopasswd.rules" ] \
    && ok "polkit rule present — pkexec-gated apps (KDE Partition Manager) work for liveuser" \
    || bad "no polkit passwordless rule for liveuser — KDE Partition Manager and other pkexec apps will fail auth"

# 2026-09-05: Wi-Fi disconnect mitigation (MacBook10,1/BCM4350 live test —
# associated then dropped seconds later) + dual-boot/manual-partition
# safety fix (those modes were UI-only stubs that silently wiped the whole
# disk instead of doing what their label promised).
[ -f "$SFS/etc/NetworkManager/conf.d/wifi-powersave-off.conf" ] \
    && ok "Wi-Fi powersave disabled on the ISO (brcmfmac disconnect mitigation)" \
    || bad "wifi-powersave-off.conf missing from the ISO"
grep -qs "^options brcmfmac roamoff=1" "$SFS/etc/modprobe.d/selah-brcmfmac-options.conf" \
    && ok "brcmfmac roamoff=1 set on the ISO (secondary disconnect mitigation)" \
    || bad "selah-brcmfmac-options.conf missing or missing roamoff=1"
grep -qs "wifi-powersave-off.conf" "$SFS/usr/local/bin/selah-setup" \
    && grep -qs "selah-brcmfmac-options.conf" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies both Wi-Fi mitigation files to installed systems" \
    || bad "installer does not propagate the Wi-Fi mitigation files to installed systems"
# 2026-09-06: Dual Boot mode was implemented for real (installs only into
# existing free space, never zaps the disk — see _existing_partnums() and
# the mode-aware Step 0 in _install()). The old check here just grepped for
# "rb.setEnabled(enabled)", a line that exists regardless of which modes are
# enabled — it would have silently passed even if Dual Boot were re-enabled
# without ever getting real logic. Check the actual invariants instead:
# Dual Boot's partitioning is mode-aware and skips zap-all, and Manual
# Partitioning (still a real stub) stays disabled.
grep -qs "if mode == 'dual':" "$SFS/usr/local/bin/selah-setup" \
    && grep -qs "_existing_partnums" "$SFS/usr/local/bin/selah-setup" \
    && ok "Dual Boot mode partitions only into free space (never zaps the disk)" \
    || bad "Dual Boot mode's free-space-only partitioning logic is missing — may wipe the disk if chosen"
grep -qs "'manual', 'Manual Partitioning (coming soon)', 'Advanced: create your own layout', False" "$SFS/usr/local/bin/selah-setup" \
    && ok "Manual Partitioning still disabled (real custom-layout logic not implemented)" \
    || bad "Manual Partitioning is selectable but still unimplemented — will wipe the disk if chosen"

# 2026-09-07: SelahSeedCore's GRUB-params/wifi-wake profile used to be
# resolved once, at install time, against whichever machine ran the
# installer -- correct for a normal fixed install, wrong for a to-go/
# portable install (e.g. Dual Boot mode) built on one machine and booted
# on another. Confirmed on real hardware: a Dual Boot install built inside
# a VM booted on a real MacBook10,1 with no Wi-Fi working, because the
# BCM4350 wake service was never enabled (the VM has no such chip to
# detect). selah-seedcore-reapply re-resolves the profile at every boot
# against the live machine and is a no-op once it already matches.
[ -x "$SFS/usr/local/bin/selah-seedcore-reapply" ] \
    && ok "exec: /usr/local/bin/selah-seedcore-reapply" \
    || bad "selah-seedcore-reapply missing or not executable"
[ -f "$SFS/etc/systemd/system/selah-seedcore-reapply.service" ] \
    && ok "selah-seedcore-reapply.service present" \
    || bad "selah-seedcore-reapply.service missing from the ISO"
grep -qs "selah-seedcore-reapply" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies + enables selah-seedcore-reapply on installed systems" \
    || bad "installer does not propagate selah-seedcore-reapply to installed systems"
grep -qs "selah-seedcore-reboot-needed" "$SFS/usr/local/bin/selahseedcore-init" \
    && ok "installed systems notify when a reboot is needed to finish a hardware-profile change" \
    || bad "selahseedcore-init does not surface the reboot-needed flag from selah-seedcore-reapply"

# 2026-09-06: CONFIRMED real-hardware root cause of the Wi-Fi "connects
# then drops" bug — WPA3-SAE handshake failure on old Broadcom firmware.
[ -f "$SFS/etc/NetworkManager/conf.d/broadcom-wpa2-default.conf" ] \
    && ok "Wi-Fi defaults to WPA2-PSK on Broadcom hardware (confirmed fix for the real connect/drop bug)" \
    || bad "broadcom-wpa2-default.conf missing — Wi-Fi will still fail on WPA2/WPA3 mixed-mode APs"
grep -qs "broadcom-wpa2-default.conf" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies the WPA2-default fix to installed systems" \
    || bad "installer does not propagate the WPA2-default fix to installed systems"

# 2026-09-06: CONFIRMED real-hardware bug — deep (S3) sleep never resumes
# on MacBook10,1 (hung forever); s2idle at least resumes kernel/network.
grep -qs '"MacBook10,1"' "$SFS/usr/share/selahos/hardware-db.json" \
    && ! (python3 -c "
import json
d = json.load(open('$SFS/usr/share/selahos/hardware-db.json'))
import sys
sys.exit(0 if 'mem_sleep_default=deep' in d['MacBook10,1']['params'] else 1)
" 2>/dev/null) \
    && ok "MacBook10,1 uses s2idle, not deep sleep (deep never resumes on this model)" \
    || bad "MacBook10,1's hardware-db.json entry still forces deep sleep, which never resumes on this model"

# 2026-09-06: CONFIRMED real-hardware bug — selah-setup copies the live
# ISO's /etc/pacman.conf (which references [chaotic-aur]'s mirrorlist) to
# the installed system, but never copied the mirrorlist file itself, so
# EVERY pacman operation failed on a real freshly-installed system with
# "config file /etc/pacman.d/chaotic-mirrorlist could not be read".
grep -qs "chaotic-mirrorlist" "$SFS/usr/local/bin/selah-setup" \
    && ok "installer copies chaotic-mirrorlist to installed systems (pacman won't be broken out of the box)" \
    || bad "installer does not copy chaotic-mirrorlist — pacman will be totally broken on every install"

echo
if [ "$fail" -eq 0 ]; then
    echo "PRE-FLIGHT PASSED — safe to flash"
else
    echo "PRE-FLIGHT FAILED — do not flash this ISO"
fi
exit "$fail"
