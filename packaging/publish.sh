#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  packaging/publish.sh — sign and publish the local package repo to
#  repo.selahos.io (hosted on web-core)
#
#  Run from the repo root, AFTER packaging/build-all.sh:
#    bash packaging/publish.sh
#
#  Design: signing happens on web-core, not here. The GPG private key
#  never leaves that box (see packaging/README.md's OTA roadmap and the
#  2026-06-17 SelahBridgePro secret-leak incident this is deliberately
#  avoiding a repeat of). This script only uploads the UNSIGNED packages
#  build-all.sh already produced, then asks web-core to sign+publish them
#  with its own key.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

HOST="${DEPLOY_HOST:-dane@web-core}"
REMOTE_DIR="/var/www/selahos-repo"
SIGNING_IDENTITY="${SELAHOS_SIGNING_IDENTITY:-packaging@selahos.io}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/repo"

TEAL=$'\033[38;2;142;195;184m'
MUTED=$'\033[38;2;154;141;123m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

ok()   { printf '  %s✓%s %s\n' "$TEAL" "$RESET" "$1"; }
info() { printf '  %s→%s %s\n' "$MUTED" "$RESET" "$1"; }

[[ -d "$REPO" ]] || { echo "✗ $REPO not found — run packaging/build-all.sh first" >&2; exit 1; }
pkgs=("$REPO"/*.pkg.tar.*)
[[ -e "${pkgs[0]}" ]] || { echo "✗ no built packages in $REPO — run packaging/build-all.sh first" >&2; exit 1; }

echo ""
echo "${BOLD}Publishing SelahOS package repo → $HOST${RESET}"
echo ""

# ── 1. Upload unsigned packages ────────────────────────────────────────────────
info "Uploading $(printf '%s\n' "${pkgs[@]}" | wc -l) package(s)..."
tar -czf /tmp/selahos-repo-publish.tar.gz -C "$REPO" $(cd "$REPO" && ls *.pkg.tar.*)

base64 /tmp/selahos-repo-publish.tar.gz | ssh "$HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
REMOTE_DIR="$1"
sudo mkdir -p "$REMOTE_DIR"
sudo chown "$(whoami)" "$REMOTE_DIR"
cd "$REMOTE_DIR"
base64 -d | tar -xzf -
REMOTE
rm /tmp/selahos-repo-publish.tar.gz
ok "Packages uploaded"

# ── 2. Sign packages + rebuild database on web-core ────────────────────────────
info "Signing packages and updating repo database (web-core's key, never leaves that box)..."
ssh "$HOST" bash -s -- "$REMOTE_DIR" "$SIGNING_IDENTITY" <<'REMOTE'
set -euo pipefail
REMOTE_DIR="$1"
SIGNING_IDENTITY="$2"
cd "$REMOTE_DIR"

for pkg in *.pkg.tar.*; do
    [[ "$pkg" == *.sig ]] && continue
    gpg --batch --yes --local-user "$SIGNING_IDENTITY" --detach-sign "$pkg"
done

rm -f selahos.db selahos.db.tar.gz selahos.db.tar.gz.old \
      selahos.files selahos.files.tar.gz selahos.files.tar.gz.old
repo-add --sign --key "$SIGNING_IDENTITY" selahos.db.tar.gz *.pkg.tar.zst *.pkg.tar.xz 2>/dev/null || \
repo-add --sign --key "$SIGNING_IDENTITY" selahos.db.tar.gz *.pkg.tar.zst
REMOTE
ok "Signed and published"

echo ""
echo "  ${MUTED}Repo contents on $HOST:${RESET}"
ssh "$HOST" "ls -1 $REMOTE_DIR" | sed 's/^/    /'
echo ""
echo "  ${TEAL}${BOLD}✓  https://repo.selahos.io is up to date${RESET}"
echo ""
