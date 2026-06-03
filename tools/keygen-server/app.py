#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
#  SelahBridgePro License Key Server
#  Serves the activation portal at selahos.io/activate (or keys.selahos.io)
#
#  Secret is read from env var SELAHPRO_SECRET — never hardcoded.
#  Set via /etc/selahpro-keygen/secret.env on the web server.
#
#  Run:   gunicorn -w 2 -b 127.0.0.1:5050 app:app
#  Dev:   SELAHPRO_SECRET=xxx flask run --port 5050
# ═══════════════════════════════════════════════════════════════════════════════

import os
import re
import hashlib
import logging
import time
from collections import defaultdict
from datetime import datetime, timezone
from functools import wraps
from pathlib import Path

from flask import Flask, request, jsonify, render_template

# ── Config ─────────────────────────────────────────────────────────────────────
SECRET = os.environ.get("SELAHPRO_SECRET", "").strip()
if not SECRET:
    raise RuntimeError(
        "SELAHPRO_SECRET environment variable not set.\n"
        "Set it in /etc/selahpro-keygen/secret.env and restart the service."
    )

LOG_FILE   = Path(os.environ.get("KEYGEN_LOG", "/var/log/selahpro-keygen.log"))
RATE_LIMIT = int(os.environ.get("RATE_LIMIT", "10"))   # requests per window
RATE_WIN   = int(os.environ.get("RATE_WINDOW", "3600")) # seconds (1 hour)

# ── App ────────────────────────────────────────────────────────────────────────
app = Flask(__name__)
app.config["JSON_SORT_KEYS"] = False

logging.basicConfig(
    filename=str(LOG_FILE),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("selahpro-keygen")

# Also log to stdout so journalctl picks it up
_stdout_handler = logging.StreamHandler()
_stdout_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_stdout_handler)

# ── Rate limiter (in-memory, per IP) ──────────────────────────────────────────
_hits: dict[str, list[float]] = defaultdict(list)

def _check_rate(ip: str) -> bool:
    now = time.monotonic()
    hits = [t for t in _hits[ip] if now - t < RATE_WIN]
    _hits[ip] = hits
    if len(hits) >= RATE_LIMIT:
        return False
    _hits[ip].append(now)
    return True

def rate_limited(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        ip = request.headers.get("X-Forwarded-For", request.remote_addr or "").split(",")[0].strip()
        if not _check_rate(ip):
            log.warning("RATE_LIMIT ip=%s", ip)
            return jsonify({"error": "Too many requests — try again later."}), 429
        return f(*args, **kwargs)
    return wrapper

# ── Key generation ─────────────────────────────────────────────────────────────
MACHINE_ID_RE = re.compile(r'^[0-9a-f]{32}$')

def _generate_key(machine_id: str) -> str:
    raw = hashlib.sha256((machine_id + SECRET).encode()).hexdigest()[:16].upper()
    return f"SELAHPRO-{raw[0:4]}-{raw[4:8]}-{raw[8:12]}-{raw[12:16]}"

# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route("/")
@app.route("/activate")
@app.route("/activate/")
def index():
    return render_template("index.html")

@app.route("/api/keygen", methods=["POST"])
@rate_limited
def api_keygen():
    data       = request.get_json(silent=True) or {}
    machine_id = (data.get("machine_id") or "").strip().lower()
    ip         = request.headers.get("X-Forwarded-For", request.remote_addr or "")

    if not machine_id:
        return jsonify({"error": "Machine ID is required."}), 400

    if not MACHINE_ID_RE.match(machine_id):
        return jsonify({
            "error": "Invalid Machine ID format. Run 'selahpro --machine-id' on your SelahOS machine."
        }), 400

    key = _generate_key(machine_id)
    ts  = datetime.now(timezone.utc).isoformat()

    log.info("KEYGEN machine_id=%s key=%s ip=%s ts=%s", machine_id, key, ip, ts)

    return jsonify({
        "key":        key,
        "machine_id": machine_id,
        "product":    "SelahBridgePro",
        "issued":     ts,
    })

@app.route("/health")
def health():
    return jsonify({"status": "ok", "product": "SelahBridgePro Keygen"}), 200

# ── Entry point ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5050, debug=False)
