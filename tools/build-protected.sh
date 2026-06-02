#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  tools/build-protected.sh — compile SelahBridgePro executables to native binaries
#
#  Run on the SelahOS build machine (Arch Linux x86_64) before each release.
#  Sources are backed up to tools/src/ (gitignored — stays on this machine only).
#  Compiled binaries replace the source files and get committed to git.
#
#  Usage:
#    cd ~/selahos-iso-repo
#    sudo bash tools/build-protected.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

GOLD=$'\033[38;2;214;168;90m'
TEAL=$'\033[38;2;142;195;184m'
MUTED=$'\033[38;2;154;141;123m'
RED=$'\033[38;2;185;122;111m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

ok()   { printf '  %s✓%s %s\n'   "$TEAL" "$RESET" "$1"; }
info() { printf '  %s→%s %s\n'   "$MUTED" "$RESET" "$1"; }
warn() { printf '  %s⚠ %s%s\n'  "$RED"  "$RESET" "$1"; }
die()  { printf '\n%s✗  %s%s\n' "$RED"  "$1" "$RESET" >&2; exit 1; }
hdr()  { printf '\n%s%s══  %s  ══%s\n' "$GOLD" "$BOLD" "$1" "$RESET"; }

# ── Must run as root ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo bash tools/build-protected.sh"
REAL_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$REAL_USER" && "$REAL_USER" != "root" ]] || \
    die "Run via sudo from your normal user account, not directly as root"

# ── Platform check ────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]]  || die "Must run on Linux (SelahOS build machine)"
[[ "$(uname -m)" == "x86_64" ]] || die "Must run on x86_64"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO_DIR/selahos-iso-v3/airootfs/usr/local/bin"
SRC_DIR="$REPO_DIR/tools/src"
INSTALL_SH="$REPO_DIR/install-selahbridgepro.sh"
TMP="$(mktemp -d /tmp/selahbridgepro-build-XXXXXX)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── Install build dependencies ────────────────────────────────────────────────
hdr "Installing build dependencies"

PKGS_NEEDED=()
for pkg in shc patchelf gcc ccache; do
    pacman -Qi "$pkg" &>/dev/null || PKGS_NEEDED+=("$pkg")
done
[[ ${#PKGS_NEEDED[@]} -eq 0 ]] || pacman -S --noconfirm --needed "${PKGS_NEEDED[@]}"
ok "shc / patchelf / gcc ready"

if ! python -m nuitka --version &>/dev/null 2>&1; then
    info "Installing nuitka..."
    pip install nuitka ordered-set --quiet
fi
ok "nuitka $(python -m nuitka --version 2>&1 | head -1)"

# ── Back up source files → tools/src/ ────────────────────────────────────────
hdr "Preserving source files → tools/src/"
mkdir -p "$SRC_DIR"

backup_if_source() {
    local name="$1" path="$2"
    [[ -f "$path" ]] || return 0
    if file "$path" | grep -qE "text|script|Python|ASCII"; then
        cp "$path" "$SRC_DIR/$name"
        ok "$name"
    else
        # Already a binary — restore source from backup for recompile
        if [[ -f "$SRC_DIR/$name" ]]; then
            info "$name already compiled — will recompile from tools/src/$name"
        else
            warn "$name appears compiled but no source backup found in tools/src/ — skipping"
        fi
    fi
}

backup_if_source "selahpro"             "$BIN_DIR/selahpro"
backup_if_source "selahbridgepro"       "$BIN_DIR/selahbridgepro"
backup_if_source "selahauth"            "$BIN_DIR/selahauth"
backup_if_source "selahwine"            "$BIN_DIR/selahwine"
backup_if_source "selah-asio-config"    "$BIN_DIR/selah-asio-config"
[[ -f "$INSTALL_SH" ]] && { cp "$INSTALL_SH" "$SRC_DIR/install-selahbridgepro.sh"; ok "install-selahbridgepro.sh"; }

# ── Compile Python scripts with Nuitka ───────────────────────────────────────
hdr "Compiling Python executables (Nuitka --onefile)"

compile_python() {
    local name="$1"; shift
    local extra_flags=("$@")
    local src="$SRC_DIR/$name"

    [[ -f "$src" ]] || { warn "No source for $name — skipping"; return; }

    info "Compiling $name  (may take a few minutes)..."
    local work="$TMP/$name"
    mkdir -p "$work/out"
    cp "$src" "$work/$name.py"

    python -m nuitka \
        --onefile \
        --assume-yes-for-downloads \
        --no-progressbar \
        --output-filename="$name" \
        --output-dir="$work/out" \
        "${extra_flags[@]}" \
        "$work/$name.py" \
        2>&1 | grep -vE "^Nuitka:(INFO|WARNING): Used|^$|Nuitka-Options|commercial" || true

    local out="$work/out/$name"
    [[ -f "$out" ]] || die "Nuitka failed to produce binary: $name"

    mv "$out" "$BIN_DIR/$name"
    chmod 700 "$BIN_DIR/$name"
    local sz; sz=$(du -sh "$BIN_DIR/$name" | cut -f1)
    ok "$name  →  $sz"
}

compile_python selahpro
compile_python selahbridgepro   --enable-plugin=pyqt6
compile_python selahauth        --enable-plugin=pyqt6

# ── Compile bash scripts with shc ─────────────────────────────────────────────
hdr "Compiling bash scripts (shc)"

compile_bash() {
    local name="$1" dest="${2:-$BIN_DIR/$1}"
    local src="${3:-$SRC_DIR/$1}"

    [[ -f "$src" ]] || { warn "No source for $name — skipping"; return; }
    info "Compiling $name..."
    shc -f "$src" -o "$dest"
    rm -f "${src}.x" "${src}.x.c" 2>/dev/null || true
    chmod 700 "$dest"
    local sz; sz=$(du -sh "$dest" | cut -f1)
    ok "$name  →  $sz"
}

compile_bash selahwine
compile_bash selah-asio-config

# ── Compile installer with shc ────────────────────────────────────────────────
hdr "Compiling installer"

INSTALL_BIN="$REPO_DIR/install-selahbridgepro"
if [[ -f "$SRC_DIR/install-selahbridgepro.sh" ]]; then
    info "Compiling install-selahbridgepro.sh..."
    shc -f "$SRC_DIR/install-selahbridgepro.sh" -o "$INSTALL_BIN"
    rm -f "${SRC_DIR}/install-selahbridgepro.sh.x" \
          "${SRC_DIR}/install-selahbridgepro.sh.x.c" 2>/dev/null || true
    chmod 755 "$INSTALL_BIN"
    sz=$(du -sh "$INSTALL_BIN" | cut -f1)
    ok "install-selahbridgepro  →  $sz"
else
    warn "No source for installer — skipping"
fi

# Remove .sh source from git tracking (it's now gitignored; binary replaces it)
if git -C "$REPO_DIR" ls-files --error-unmatch install-selahbridgepro.sh &>/dev/null 2>&1; then
    git -C "$REPO_DIR" rm --cached install-selahbridgepro.sh
    ok "install-selahbridgepro.sh untracked from git"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n%s%s══════════════════════════════════════════════════════%s\n' \
    "$TEAL" "$BOLD" "$RESET"
printf '  %s%s✓  All executables compiled — repo ready to commit%s\n' \
    "$TEAL" "$BOLD" "$RESET"
printf '%s══════════════════════════════════════════════════════%s\n\n' \
    "$TEAL" "$RESET"

printf '  %sSource files preserved at:%s  tools/src/  (gitignored)\n' "$MUTED" "$RESET"
printf '  %sTo update source:%s edit tools/src/, then re-run this script\n\n' "$MUTED" "$RESET"

printf '  %sCommit and push compiled binaries:%s\n\n' "$MUTED" "$RESET"
printf '    git add selahos-iso-v3/airootfs/usr/local/bin/selahpro \\\n'
printf '            selahos-iso-v3/airootfs/usr/local/bin/selahbridgepro \\\n'
printf '            selahos-iso-v3/airootfs/usr/local/bin/selahauth \\\n'
printf '            selahos-iso-v3/airootfs/usr/local/bin/selahwine \\\n'
printf '            selahos-iso-v3/airootfs/usr/local/bin/selah-asio-config \\\n'
printf '            install-selahbridgepro\n'
printf '    git commit -m "Build: compile all executables to native binaries"\n'
printf '    git push\n\n'
