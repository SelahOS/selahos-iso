#!/usr/bin/env bash
# ============================================================
# selah-remote-dev-setup.sh — make ONE SelahOS machine reachable for remote
# development (B-49). Run it once, on the Mac, as root:
#
#   sudo bash selah-remote-dev-setup.sh --pubkey-file ~/dev.pub
#   sudo bash selah-remote-dev-setup.sh --undo
#
# What it does (each step is idempotent):
#   1. installs openssh (+ tailscale unless --no-tailscale)
#   2. sshd drop-in: KEY-ONLY login, no root login, ONLY the dev user
#   3. adds the given public key to that user's authorized_keys
#   4. optional passwordless sudo for that user (--sudo all, the default)
#   5. masks suspend/hibernate so the machine stays reachable
#   6. enables sshd + tailscaled and joins the tailnet
#   7. --tailnet-only: refuse SSH from anywhere but the tailnet/loopback
#   8. prints a summary (model, link type, tailnet name, key fingerprint)
#
# SECURITY, plainly: "--sudo all" makes whoever holds the matching PRIVATE key
# root-equivalent on this machine. Use it on a throwaway test install only —
# never a machine with personal data. Login is key-only for one user, and
# --tailnet-only limits who can even reach sshd.
#
# Options:
#   --pubkey-file FILE   REQUIRED (except --undo). One OpenSSH public key.
#   --user NAME          dev user (default: the user who ran sudo)
#   --sudo all|none      passwordless sudo for that user (default: all)
#   --no-tailscale       skip tailscale
#   --ts-authkey-file F  tailscale pre-auth key read from a file (unattended)
#   --hostname NAME      tailnet name (default: selahmac-<model>, e.g. selahmac-imac16-2)
#   --tailnet-only       only accept SSH from tailnet + loopback
#   --keep-awake no      do NOT mask suspend/hibernate
#   --dry-run            print what would change, change nothing (no root needed)
#   --undo               remove what this script added (leaves packages + tailscale)
#
# Testing hook: SELAH_TEST_ROOT=/some/dir writes every file under that dir and
# skips packages/services/chown, so the file generation can be checked without root.
# ============================================================
set -uo pipefail

PUBKEY_FILE=""; DEV_USER="${SUDO_USER:-}"; SUDO_MODE=all; USE_TS=1; TS_KEY_FILE=""
TS_HOST=""; TAILNET_ONLY=0; KEEP_AWAKE=yes; DRY=0; UNDO=0
R="${SELAH_TEST_ROOT:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --pubkey-file) PUBKEY_FILE="${2:-}"; shift 2 ;;
    --user) DEV_USER="${2:-}"; shift 2 ;;
    --sudo) SUDO_MODE="${2:-}"; shift 2 ;;
    --no-tailscale) USE_TS=0; shift ;;
    --ts-authkey-file) TS_KEY_FILE="${2:-}"; shift 2 ;;
    --hostname) TS_HOST="${2:-}"; shift 2 ;;
    --tailnet-only) TAILNET_ONLY=1; shift ;;
    --keep-awake) KEEP_AWAKE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --undo) UNDO=1; shift ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 64 ;;
  esac
done

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
LIVE=1; { [ "$DRY" = 1 ] || [ -n "$R" ]; } && LIVE=0     # LIVE=1 => really change the system
# do(): run a system-changing command only when LIVE (services, packages, chown...)
do_() { if [ "$LIVE" = 1 ]; then "$@"; else info "[skipped: $*]"; fi; }
# put(): write stdin to a file only when not a dry run
put() { local f="$1" mode="${2:-644}"; if [ "$DRY" = 1 ]; then info "[dry-run] would write $f"; cat >/dev/null; return; fi
        mkdir -p "$(dirname "$f")"; cat > "$f"; chmod "$mode" "$f"; info "wrote $f"; }

[ "$LIVE" = 1 ] && [ "$(id -u)" -ne 0 ] && die "run as root: sudo bash $0 ..."
[ -n "$DEV_USER" ] || die "cannot tell which user to set up — pass --user NAME"
id "$DEV_USER" >/dev/null 2>&1 || die "no such user: $DEV_USER"
[ "$DEV_USER" = root ] && die "refusing to set up root; use a normal user"
HOME_DIR="$(getent passwd "$DEV_USER" | cut -d: -f6)"
DEV_GROUP="$(id -gn "$DEV_USER")"
MODEL="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
[ -n "$TS_HOST" ] || TS_HOST="selahmac-$(echo "$MODEL" | tr 'A-Z,' 'a-z-' | tr -cd 'a-z0-9-')"

SSHD_DROPIN="$R/etc/ssh/sshd_config.d/50-selah-remote-dev.conf"
SSHD_MAIN="$R/etc/ssh/sshd_config"
SUDOERS_FILE="$R/etc/sudoers.d/90-selah-remote-dev"
AUTH_KEYS="$R$HOME_DIR/.ssh/authorized_keys"
STATE="$R/var/lib/selah-remote-dev/state"
MARK="# selah-remote-dev"
INCLUDE_LINE="Include /etc/ssh/sshd_config.d/*.conf $MARK"
LOG="$R/var/log/selah-remote-dev-setup.log"
[ "$LIVE" = 1 ] && { mkdir -p "$(dirname "$LOG")"; exec > >(tee -a "$LOG") 2>&1; }
echo "selah-remote-dev-setup  $(date '+%F %T')  user=$DEV_USER  model=$MODEL  dry-run=$DRY  undo=$UNDO"

# ------------------------------------------------------------------ undo
if [ "$UNDO" = 1 ]; then
  step "Removing what selah-remote-dev-setup added"
  if [ "$DRY" = 1 ]; then info "[dry-run] would remove drop-in, sudoers file, marked keys; unmask units we masked"; exit 0; fi
  rm -f "$SSHD_DROPIN" "$SUDOERS_FILE" && info "removed sshd drop-in and sudoers file"
  [ -f "$SSHD_MAIN" ] && sed -i "\|$MARK|d" "$SSHD_MAIN"
  [ -f "$AUTH_KEYS" ] && sed -i "\|$MARK|d" "$AUTH_KEYS" && info "removed marked keys from $AUTH_KEYS"
  if [ -f "$STATE" ]; then
    for u in $(grep '^masked=' "$STATE" | cut -d= -f2); do do_ systemctl unmask "$u"; done
    rm -f "$STATE"
  fi
  do_ systemctl reload sshd
  echo; echo "Done. sshd, openssh and tailscale were left installed/enabled; run 'sudo systemctl disable --now sshd' to turn SSH off."
  exit 0
fi

# ---------------------------------------------------------------- checks
[ -n "$PUBKEY_FILE" ] || die "--pubkey-file is required (see --help)"
[ -r "$PUBKEY_FILE" ] || die "cannot read $PUBKEY_FILE"
case "$SUDO_MODE" in all|none) ;; *) die "--sudo must be 'all' or 'none'" ;; esac
[ "$(grep -c . "$PUBKEY_FILE")" -eq 1 ] || die "$PUBKEY_FILE must contain exactly ONE public key line"
KEYLINE="$(grep . "$PUBKEY_FILE" | head -1)"
case "$KEYLINE" in ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-*\ *) ;; *) die "$PUBKEY_FILE does not look like an OpenSSH PUBLIC key" ;; esac
FPR="$(ssh-keygen -l -f "$PUBKEY_FILE" 2>/dev/null)" || die "ssh-keygen could not read the key in $PUBKEY_FILE (is it a private key by mistake?)"

# ------------------------------------------------------------- 1. packages
step "1/8 Packages"
if [ "$LIVE" = 1 ]; then
  pkgs=(openssh); [ "$USE_TS" = 1 ] && pkgs+=(tailscale)
  pacman -S --needed --noconfirm "${pkgs[@]}" || die "package install failed (network up? try again)"
else info "[skipped: pacman -S --needed openssh$( [ "$USE_TS" = 1 ] && echo ' tailscale')]"; fi

# ------------------------------------------------------------- 2. sshd
step "2/8 sshd: key-only, one user"
# Arch's sshd_config includes sshd_config.d; make sure ours is honoured.
if [ "$DRY" = 0 ] && [ -f "$SSHD_MAIN" ] && ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_MAIN"; then
  sed -i "1i $INCLUDE_LINE" "$SSHD_MAIN"; info "added the missing Include line to $SSHD_MAIN"
fi
{
  echo "# managed by selah-remote-dev-setup.sh — remove with: sudo bash selah-remote-dev-setup.sh --undo"
  echo "PasswordAuthentication no"
  echo "KbdInteractiveAuthentication no"
  echo "PermitRootLogin no"
  echo "PubkeyAuthentication yes"
  echo "AllowUsers $DEV_USER"
  if [ "$TAILNET_ONLY" = 1 ]; then
    echo "# --tailnet-only: anything that is not the tailnet or loopback is refused"
    echo "Match Address *,!100.64.0.0/10,!fd7a:115c:a1e0::/48,!127.0.0.0/8,!::1"
    echo "    DenyUsers *"
  fi
} | put "$SSHD_DROPIN" 644
if [ "$LIVE" = 1 ]; then
  sshd -t || { rm -f "$SSHD_DROPIN"; die "sshd rejected the new config; removed it, nothing changed"; }
  info "sshd -t: config OK"
fi

# --------------------------------------------------------- 3. authorized key
step "3/8 authorized key for $DEV_USER"
if [ "$DRY" = 1 ]; then info "[dry-run] would add key: $FPR"
else
  mkdir -p "$(dirname "$AUTH_KEYS")"; touch "$AUTH_KEYS"
  if grep -qF "$KEYLINE" "$AUTH_KEYS"; then info "key already present"; else echo "$KEYLINE $MARK" >> "$AUTH_KEYS"; info "added key"; fi
  chmod 600 "$AUTH_KEYS"; chmod 700 "$(dirname "$AUTH_KEYS")"
  do_ chown -R "$DEV_USER:$DEV_GROUP" "$(dirname "$AUTH_KEYS")"
fi

# -------------------------------------------------------------- 4. sudo
step "4/8 sudo"
if [ "$SUDO_MODE" = all ]; then
  echo "$DEV_USER ALL=(ALL) NOPASSWD: ALL" | put "$SUDOERS_FILE" 440
  if [ "$LIVE" = 1 ]; then visudo -cf "$SUDOERS_FILE" >/dev/null || { rm -f "$SUDOERS_FILE"; die "sudoers check failed; removed"; }; info "visudo: OK"; fi
  info "NOTE: this makes the holder of the private key root-equivalent on this machine."
else info "--sudo none: no sudoers entry written"; fi

# ------------------------------------------------------------- 5. sleep
step "5/8 keep the machine awake"
if [ "$KEEP_AWAKE" = no ]; then info "--keep-awake no: leaving sleep alone"
else
  units=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
  if [ "$DRY" = 0 ]; then mkdir -p "$(dirname "$STATE")"; touch "$STATE"; fi
  for u in "${units[@]}"; do
    if [ "$LIVE" = 1 ] && [ "$(systemctl is-enabled "$u" 2>/dev/null)" = masked ]; then info "$u already masked (left as is)"; continue; fi
    do_ systemctl mask "$u"; [ "$DRY" = 0 ] && ! grep -qx "masked=$u" "$STATE" && echo "masked=$u" >> "$STATE"
  done
fi

# --------------------------------------------- 6. services + tailscale
step "6/8 services"
do_ systemctl enable --now sshd
if [ "$USE_TS" = 1 ]; then
  do_ systemctl enable --now tailscaled
  if [ "$LIVE" = 1 ]; then
    if tailscale status >/dev/null 2>&1 && ! tailscale status 2>&1 | grep -qiE 'logged out|needs login'; then
      info "already on a tailnet"
    else
      info "joining the tailnet as '$TS_HOST' ..."
      if [ -n "$TS_KEY_FILE" ]; then tailscale up --hostname="$TS_HOST" --auth-key="file:$TS_KEY_FILE"
      else info ">>> A login URL will be printed. Open it on any device signed in to your Tailscale account."; tailscale up --hostname="$TS_HOST"; fi
    fi
  else info "[skipped: tailscale up --hostname=$TS_HOST]"; fi
else info "--no-tailscale: not joining a tailnet"; fi

# ------------------------------------------------------------- 7/8 summary
step "7/8 verify"
if [ "$LIVE" = 1 ]; then
  systemctl is-active --quiet sshd && info "sshd: active" || info "WARNING: sshd is NOT active"
  ss -ltn 2>/dev/null | grep -q ':22 ' && info "listening on port 22" || info "WARNING: nothing listening on port 22"
fi
step "8/8 summary"
DEF_IF="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
LINK="unknown"; [ -n "$DEF_IF" ] && { [ -d "/sys/class/net/$DEF_IF/wireless" ] && LINK="WI-FI" || LINK="wired"; }
TS_IP="$(tailscale ip -4 2>/dev/null | head -1)"
echo "  model            : $MODEL"
echo "  dev user         : $DEV_USER   (sudo: $SUDO_MODE)"
echo "  default route    : ${DEF_IF:-none} ($LINK)"
echo "  authorized key   : $FPR"
echo "  tailnet name/IP  : $TS_HOST / ${TS_IP:-not joined yet}"
echo "  tailnet-only ssh : $([ "$TAILNET_ONLY" = 1 ] && echo yes || echo 'no (sshd answers on every interface; key-only)')"
echo "  connect with     : ssh $DEV_USER@${TS_IP:-$TS_HOST}"
[ "$LINK" = "WI-FI" ] && echo "  !! The default route is Wi-Fi. Plug in Ethernet before any Wi-Fi/driver work, or a driver change will cut this link."
echo "  undo later with  : sudo bash $0 --undo"
[ "$LIVE" = 1 ] && echo "  log              : $LOG"
exit 0
