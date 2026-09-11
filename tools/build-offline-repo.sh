#!/usr/bin/env bash
# build-offline-repo.sh — builds the on-ISO offline package repo consumed
# at install time via [selahos-offline] in airootfs/etc/pacman.conf.
#
# Why this exists (2026-09-04): selah-setup used to pacstrap ~90 packages
# fresh from network mirrors during every install, with no local fallback
# at all. That's both a hard requirement for internet access the user
# explicitly doesn't want, and the direct cause of a real install crash —
# pipewire-jack and jack2 both provide the same `jack` library and
# explicitly conflict, and live-mirror-state-dependent dependency
# resolution let jack2 get pulled into the same non-interactive pacstrap
# transaction on at least one real install. Bundling a fixed, versioned,
# internally-consistent package set on the ISO itself fixes both: no
# network needed for the packages selah-setup actually requests, and the
# exact set of what's available is decided once, here, not re-resolved
# against whatever mirrors happen to serve on install day.
#
# Run by rebuild-iso.sh BEFORE mkarchiso, using the SAME pacman.conf
# mkarchiso itself uses to build the live squashfs (selahos-iso-v3/
# pacman.conf, not the shipped airootfs one) — this freezes package
# versions from one consistent mirror snapshot, avoiding a mismatch
# between what the live environment ships and what this bundle contains.
#
# Usage: sudo bash tools/build-offline-repo.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$(cd "$SCRIPT_DIR/../selahos-iso-v3" && pwd)"
PKGLIST_DIR="$PROFILE_DIR/airootfs/usr/local/share/selahos-install-packages"
OUT_DIR="$PROFILE_DIR/airootfs/usr/local/share/selahos-offline-repo"
BUILD_PACMAN_CONF="$PROFILE_DIR/pacman.conf"
SCRATCH_DB="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DB"' EXIT

echo "==> Collecting package list (base + base-apple-extra + kde + audio + wine)..."
PACKAGES=()
for f in base base-apple-extra kde audio wine; do
  while IFS= read -r line; do
    pkg="$(echo "${line%%#*}" | xargs)"
    [ -n "$pkg" ] && PACKAGES+=("$pkg")
  done < "$PKGLIST_DIR/$f.txt"
done
echo "    ${#PACKAGES[@]} top-level packages requested (both is_apple branches included —"
echo "    hardware isn't known until install time, so the bundle covers either path)"

mkdir -p "$OUT_DIR"

echo "==> Syncing package databases into an isolated dbpath (won't touch this host's own pacman state)..."
pacman --config "$BUILD_PACMAN_CONF" --dbpath "$SCRATCH_DB" -Sy

echo "==> Downloading packages + full dependency closure into $OUT_DIR..."
# --cachedir (not the host's real cache) + download-only (-Sw): this must
# be a self-contained bundle independent of what's already on this dev
# machine, not a "top up what's missing" operation.
#
# 2026-09-04: --noconfirm alone only suppresses the final "Proceed?"
# prompt — it does NOT suppress "N providers available, pick one"
# prompts (several packages here pull in a virtual dependency with
# multiple real providers, e.g. tessdata has 128). Confirmed live: with
# stdin still attached to an interactive terminal, pacman happily sits
# and asks each one, requiring someone to babysit the run and press
# Enter repeatedly. Redirecting stdin from /dev/null makes pacman detect
# non-interactive mode and take the default (option 1) for every such
# prompt automatically, same as it already does for the confirm prompt.
pacman --config "$BUILD_PACMAN_CONF" --dbpath "$SCRATCH_DB" --cachedir "$OUT_DIR" \
  -Sw --noconfirm "${PACKAGES[@]}" < /dev/null

echo "==> Structurally excluding jack2 (see the header comment above) — confirmed safe:"
echo "    pipewire-jack (bundled, in audio.txt) provides the identical jack/libjack.so"
echo "    set jack2 does, so nothing is left unsatisfied by removing it here."
rm -f "$OUT_DIR"/jack2-*.pkg.tar.*

echo "==> Building repo database (repo-add)..."
cd "$OUT_DIR"
rm -f selahos-offline.db selahos-offline.db.tar.gz selahos-offline.db.tar.gz.old \
      selahos-offline.files selahos-offline.files.tar.gz selahos-offline.files.tar.gz.old
shopt -s nullglob
pkgfiles=(./*.pkg.tar.zst ./*.pkg.tar.xz)
shopt -u nullglob
if [ "${#pkgfiles[@]}" -eq 0 ]; then
  echo "ERROR: no package files ended up in $OUT_DIR — something went wrong above." >&2
  exit 1
fi
repo-add -q selahos-offline.db.tar.gz "${pkgfiles[@]}"

echo "==> Done. Offline repo: $OUT_DIR ($(du -sh "$OUT_DIR" | cut -f1), ${#pkgfiles[@]} packages)"
