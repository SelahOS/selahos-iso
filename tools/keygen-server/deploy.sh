#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  tools/keygen-server/deploy.sh — deploy SelahBridgePro keygen to web server
#  Run from the repo root: bash tools/keygen-server/deploy.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

HOST="${DEPLOY_HOST:-dane@web-core}"
REMOTE_DIR="/var/www/selahpro-keygen"
SECRET_FILE="$(dirname "$0")/../../selahos-iso-v3/airootfs/etc/selahbridgepro/.keydata"

TEAL=$'\033[38;2;142;195;184m'
MUTED=$'\033[38;2;154;141;123m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

ok()   { printf '  %s✓%s %s\n' "$TEAL" "$RESET" "$1"; }
info() { printf '  %s→%s %s\n' "$MUTED" "$RESET" "$1"; }

[[ -f "$SECRET_FILE" ]] || { echo "✗ .keydata not found at $SECRET_FILE" >&2; exit 1; }
SECRET=$(cat "$SECRET_FILE")
[[ -n "$SECRET" ]] || { echo "✗ .keydata is empty — run tools/selahpro-keygen-deploy.sh --deploy first" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "${BOLD}Deploying SelahBridgePro Keygen → $HOST${RESET}"
echo ""

# ── 1. Upload app files ───────────────────────────────────────────────────────
info "Uploading app files..."
tar -czf /tmp/selahpro-keygen-deploy.tar.gz \
    -C "$SCRIPT_DIR" \
    app.py requirements.txt templates/

# Use base64 pipe (no scp needed — matches web server deploy pattern)
base64 /tmp/selahpro-keygen-deploy.tar.gz | ssh "$HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
REMOTE_DIR="$1"
mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"
base64 -d | tar -xzf -
REMOTE
rm /tmp/selahpro-keygen-deploy.tar.gz
ok "App files uploaded"

# ── 2. Set up virtualenv and install deps ─────────────────────────────────────
info "Installing Python dependencies..."
ssh "$HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
cd "$1"
[[ -d venv ]] || python3 -m venv venv
./venv/bin/pip install -q -r requirements.txt
REMOTE
ok "Dependencies installed"

# ── 3. Write secret env file ──────────────────────────────────────────────────
info "Writing secret env file..."
ssh "$HOST" bash -s -- "$SECRET" <<'REMOTE'
set -euo pipefail
sudo mkdir -p /etc/selahpro-keygen
printf 'SELAHPRO_SECRET=%s\nKEYGEN_LOG=/var/log/selahpro-keygen.log\n' "$1" \
    | sudo tee /etc/selahpro-keygen/secret.env > /dev/null
sudo chmod 600 /etc/selahpro-keygen/secret.env
sudo chown root:www-data /etc/selahpro-keygen/secret.env
sudo touch /var/log/selahpro-keygen.log
sudo chown www-data:www-data /var/log/selahpro-keygen.log
REMOTE
ok "Secret env file written"

# ── 4. Install and restart systemd service ────────────────────────────────────
info "Installing systemd service..."
ssh "$HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
sudo cp "$1/selahpro-keygen.service" /etc/systemd/system/selahpro-keygen.service
sudo chown -R www-data:www-data "$1"
sudo systemctl daemon-reload
sudo systemctl enable --now selahpro-keygen
sudo systemctl restart selahpro-keygen
sleep 1
sudo systemctl is-active selahpro-keygen
REMOTE
ok "Service running"

# ── 5. Nginx config hint ──────────────────────────────────────────────────────
echo ""
echo "  ${MUTED}Nginx config not auto-applied.${RESET}"
echo "  Review tools/keygen-server/nginx-keygen.conf and apply manually:"
echo "  ${TEAL}scp tools/keygen-server/nginx-keygen.conf $HOST:/etc/nginx/sites-available/selahpro-keygen${RESET}"
echo "  ${TEAL}ssh $HOST 'sudo ln -sf /etc/nginx/sites-available/selahpro-keygen /etc/nginx/sites-enabled/ && sudo nginx -t && sudo systemctl reload nginx'${RESET}"
echo ""
echo "  ${TEAL}${BOLD}✓  Deployment complete — keygen listening on 127.0.0.1:5050${RESET}"
echo ""
