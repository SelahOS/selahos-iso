#!/usr/bin/env bash
# rebuild-iso.sh — clean rebuild of the SelahOS ISO from selahos-iso-v3,
# then run the pre-flash preflight gate against the result.
#
# Usage:  sudo bash ~/selah-build.sh            (thin wrapper around this file)
#         bash tools/rebuild-iso.sh --dry-run   (no root, changes nothing:
#                                                checks + prints the plan)
# Env:    KEEP_WORK=1  keep the ~20 GB mkarchiso work dir after a good build
#
# Everything is derived from this file's location and the invoking user's
# home, so it works on any machine (the old version hardcoded /home/dbnoble).
#
# What it does, in order:
#   1. sanity checks (tools, free disk) + safe removal of any stale work dir
#   2. repairs profile local-repo/ from the versions pinned in packages.x86_64
#      (the committed selah-local.db points at a tarball that was never
#      committed, and the pinned linux-zen package itself is not in git)
#   3. builds a temp pacman.conf whose [selah-local] path is correct here
#   4. builds the offline package repo bundled on the ISO
#   5. mkarchiso, then iso-preflight.sh — the exit code is the preflight's
set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="$REPO_ROOT/selahos-iso-v3"
LOCAL_REPO="$PROFILE/local-repo"
RUN_USER="${SUDO_USER:-$(stat -c %U "$REPO_ROOT")}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
WORK="$RUN_HOME/selahos-work"
OUT="$RUN_HOME/selahos-iso-output"
LOG="$RUN_HOME/selahos-build-log.txt"
ALA="https://archive.archlinux.org/packages"
MIN_FREE_GB=45

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
run()  { if [[ $DRY -eq 1 ]]; then echo "   [dry-run] $*"; else "$@"; fi; }

[[ $DRY -eq 1 ]] || exec > >(tee "$LOG") 2>&1
echo "SelahOS ISO rebuild  $(date '+%F %T')  user=$RUN_USER  dry-run=$DRY"
echo "profile=$PROFILE"
echo "work=$WORK  out=$OUT  log=$LOG"

# ---------------------------------------------------------------- 1. checks
step "Checking prerequisites"
for c in mkarchiso mksquashfs xorriso mkfs.fat mcopy grub-mkstandalone repo-add curl findmnt; do
  command -v "$c" >/dev/null || die "missing tool: $c (pacman -S archiso ... )"
done
[[ -f "$PROFILE/profiledef.sh" ]] || die "no profile at $PROFILE"
# Build inputs that are gitignored ON PURPOSE (SelahBridge is the protected
# product and this repo is public) but that every real ISO needs. A fresh
# checkout silently lacks them: the 2026-09-20 test ISO shipped without them
# (selahpro then logs "selahbridge-install not found") while the released
# 2.0.1 ISO had them. They can be recovered from any released ISO's
# airootfs.sfs. NEVER commit these.
_missing=()
for _f in etc/selahbridgepro/.keydata usr/local/bin/selahbridge-install \
          usr/local/bin/selahbridge-winapp usr/local/bin/selahbridge-detect \
          usr/local/bin/selahbridge-sandbox; do
  [[ -e "$PROFILE/airootfs/$_f" ]] || _missing+=("$_f")
done
if [[ ${#_missing[@]} -gt 0 ]]; then
  echo "   WARNING: gitignored build inputs missing from airootfs (this ISO will lack them):"
  printf '            %s\n' "${_missing[@]}"
  echo "            Fine for a throwaway test ISO. A RELEASE ISO must not be built like this."
fi
if git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -qv '^??'; then
  echo "   NOTE: uncommitted changes in $REPO_ROOT will be built into the ISO."
fi

# A failed mkarchiso can leave bind-mounts under the work dir; rm -rf through
# one would delete REAL system files. Unmount everything under $WORK, and
# refuse to delete if anything is still mounted.
step "Removing stale work/output dirs"
mounted() { findmnt -rn -o TARGET | awk -v w="$WORK" 'index($0, w "/")==1 || $0==w' | sort -r; }
if [[ $DRY -eq 0 && -e "$WORK" ]]; then
  while read -r m; do [[ -n "$m" ]] && { umount "$m" 2>/dev/null || umount -l "$m" || true; }; done < <(mounted)
  [[ -z "$(mounted)" ]] || die "mounts still present under $WORK — not deleting. Reboot, then rerun."
fi
run rm -rf "$WORK" "$OUT"

avail=$(df -BG --output=avail "$RUN_HOME" | tail -1 | tr -dc 0-9)
echo "   free space on $RUN_HOME: ${avail} GB (need >= ${MIN_FREE_GB})"
[[ "$avail" -ge "$MIN_FREE_GB" ]] || die "not enough free disk — free some space first (see ~/DISK_CLEANUP_TODO.md)"

# ------------------------------------------------------- 2. local-repo repair
# packages.x86_64 pins e.g. linux-zen=7.0.9.zen1-1. Arch mirrors only carry the
# newest kernel, so the pinned files come from local-repo, this host's pacman
# cache, or the Arch Linux Archive, in that order.
step "Repairing profile local-repo (pinned packages + database)"
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Za-z0-9@._+-]+)=([^[:space:]]+)$ ]] || continue
  name="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[2]}"
  pkg="$name-$ver-x86_64.pkg.tar.zst"
  if [[ -f "$LOCAL_REPO/$pkg" ]]; then
    echo "   have   $pkg (local-repo)"
  elif [[ -f "/var/cache/pacman/pkg/$pkg" ]]; then
    echo "   copy   $pkg (pacman cache)"
    run cp "/var/cache/pacman/pkg/$pkg" "$LOCAL_REPO/$pkg"
  else
    echo "   fetch  $pkg (Arch Linux Archive)"
    run curl -fL --retry 3 -o "$LOCAL_REPO/$pkg" "$ALA/${name:0:1}/$name/$pkg"
  fi
done < "$PROFILE/packages.x86_64"

# Packages we build ourselves (./packaging/<name>/) that the install lists
# request but no sync repo carries. Missing from selah-local, the offline-repo
# build dies with "error: target not found: <name>" (seen 2026-09-20).
LOCAL_BUILT=(snd-hda-macbook12-dkms-git)
for name in "${LOCAL_BUILT[@]}"; do
  if compgen -G "$LOCAL_REPO/$name-*.pkg.tar.zst" >/dev/null; then
    echo "   have   $name (local-repo)"
    continue
  fi
  src="$(ls -t "$REPO_ROOT"/packaging/"$name"/"$name"-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
  [[ -f "$src" ]] || die "no built package for $name in packaging/$name/ — run makepkg there first"
  echo "   copy   $(basename "$src") (packaging/)"
  run cp "$src" "$LOCAL_REPO/"
done
if [[ $DRY -eq 0 ]]; then
  ( cd "$LOCAL_REPO" && repo-add -q selah-local.db.tar.gz ./*.pkg.tar.zst )
  chown -R "$RUN_USER": "$LOCAL_REPO"
  echo "   selah-local database: $(tar -tzf "$LOCAL_REPO/selah-local.db.tar.gz" | grep -c '/$') packages"
fi

# ------------------------------------------------------ 3. per-machine config
step "Generating pacman.conf with this machine's [selah-local] path"
TMPCONF="$(mktemp /tmp/selah-pacman.XXXXXX.conf)"
trap 'rm -f "$TMPCONF"' EXIT
sed -E "s|^(Server = file://).*/local-repo\$|\1$LOCAL_REPO|" "$PROFILE/pacman.conf" > "$TMPCONF"
grep -qx "Server = file://$LOCAL_REPO" "$TMPCONF" || die "could not rewrite [selah-local] Server line in pacman.conf"
grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' "$TMPCONF" && [[ ! -r /etc/pacman.d/chaotic-mirrorlist ]] \
  && die "/etc/pacman.d/chaotic-mirrorlist missing on this machine"
echo "   [selah-local] -> file://$LOCAL_REPO"
export BUILD_PACMAN_CONF="$TMPCONF"

# --------------------------------------------------------- 4. offline repo
step "Building offline package repo (bundled on the ISO for network-free installs)"
run bash "$SCRIPT_DIR/build-offline-repo.sh"

# ------------------------------------------------------------- 5. the ISO
step "Building ISO with mkarchiso"
run mkarchiso -v -w "$WORK" -o "$OUT" -C "$TMPCONF" "$PROFILE"

if [[ $DRY -eq 1 ]]; then
  step "Dry run complete — nothing was changed, nothing was built"
  exit 0
fi

ISO="$(ls -t "$OUT"/*.iso 2>/dev/null | head -1)"
[[ -f "$ISO" ]] || die "mkarchiso finished but no ISO in $OUT"
step "Build finished: $ISO ($(du -h "$ISO" | cut -f1)) — running preflight gate"
set +e
bash "$SCRIPT_DIR/iso-preflight.sh" "$ISO"
rc=$?
set -e

( cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256" )
chown -R "$RUN_USER": "$OUT" "$LOG" 2>/dev/null || true
[[ "${KEEP_WORK:-0}" == 1 ]] || { echo "==> Removing work dir (KEEP_WORK=1 to keep it)"; rm -rf "$WORK"; }

echo
[[ $rc -eq 0 ]] && echo "RESULT: build OK, preflight PASSED — $ISO" \
                || echo "RESULT: build finished but PREFLIGHT FAILED (exit $rc) — do not use this ISO"
echo "Log: $LOG"
exit "$rc"
