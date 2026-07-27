#!/usr/bin/env bash
# ============================================================
# build-all.sh — build every SelahOS package and assemble a
# local pacman repository at packaging/repo/.
#
# Usage:  bash ~/SelahOS-Dev/packaging/build-all.sh
# (no sudo — makepkg refuses to run as root)
#
# Result: packaging/repo/selahos.db + *.pkg.tar.zst, usable as:
#   [selahos]
#   SigLevel = Never          # until repo signing is set up
#   Server = file:///home/dbnoble/SelahOS-Dev/packaging/repo
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/repo"
PKGS=(selah-apps selah-device-editors selah-theme selah-tools)

[ "$(id -u)" -eq 0 ] && { echo "run WITHOUT sudo — makepkg refuses root"; exit 1; }

mkdir -p "$REPO"
built=()

for p in "${PKGS[@]}"; do
    echo "==> building $p"
    ( cd "$HERE/$p" && rm -rf pkg src && \
      PKGDEST="$REPO" makepkg -f --nodeps --noconfirm >/dev/null )
    f=$(ls -t "$REPO/$p"-*.pkg.tar.* 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "!! $p produced no package"; exit 1; }
    built+=("$f")
    echo "    $(basename "$f")"
done

echo "==> updating repo database"
repo-add -q "$REPO/selahos.db.tar.gz" "${built[@]}"

echo "==> done. Repo contents:"
ls -1 "$REPO"
echo
echo "To test locally, add to /etc/pacman.conf:"
echo "  [selahos]"
echo "  SigLevel = Never"
echo "  Server = file://$REPO"
echo "then:  sudo pacman -Sy"
