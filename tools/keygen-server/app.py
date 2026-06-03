#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
#  SelahBridgePro License Key Server — stdlib only, no dependencies
#  Handles POST /keygen  (HTML served statically by nginx)
#
#  Config via environment variables:
#    SELAHPRO_SECRET   — required, the license signing secret
#    KEYGEN_PORT       — port to listen on (default 5050)
#    KEYGEN_LOG        — log file path (default ~/logs/selahpro-keygen.log)
#    RATE_LIMIT        — max requests per IP per hour (default 10)
# ═══════════════════════════════════════════════════════════════════════════════

import hashlib
import json
import logging
import os
import re
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# ── Config ─────────────────────────────────────────────────────────────────────
SECRET = os.environ.get("SELAHPRO_SECRET", "").strip()
if not SECRET:
    sys.exit("SELAHPRO_SECRET env var not set — aborting")

PORT        = int(os.environ.get("KEYGEN_PORT", "5050"))
RATE_LIMIT  = int(os.environ.get("RATE_LIMIT", "10"))
RATE_WINDOW = 3600

LOG_PATH = Path(os.environ.get(
    "KEYGEN_LOG",
    Path.home() / "logs" / "selahpro-keygen.log"
))
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler(sys.stdout),
    ],
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("keygen")

# ── Rate limiter ───────────────────────────────────────────────────────────────
_hits: dict[str, list[float]] = defaultdict(list)

def _rate_ok(ip: str) -> bool:
    now   = time.monotonic()
    valid = [t for t in _hits[ip] if now - t < RATE_WINDOW]
    _hits[ip] = valid
    if len(valid) >= RATE_LIMIT:
        return False
    _hits[ip].append(now)
    return True

# ── Key generation ─────────────────────────────────────────────────────────────
MACHINE_ID_RE = re.compile(r'^[0-9a-f]{32}$')

def _make_key(machine_id: str) -> str:
    raw = hashlib.sha256((machine_id + SECRET).encode()).hexdigest()[:16].upper()
    return f"SELAHPRO-{raw[0:4]}-{raw[4:8]}-{raw[8:12]}-{raw[12:16]}"

# ── HTTP handler ───────────────────────────────────────────────────────────────

class KeygenHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # suppress default per-request stderr noise

    def _json(self, code: int, data: dict) -> None:
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path in ("/health", "/health/"):
            self._json(200, {"status": "ok"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path not in ("/keygen", "/keygen/"):
            self._json(404, {"error": "not found"})
            return

        ip = (
            self.headers.get("X-Forwarded-For", "").split(",")[0].strip()
            or self.client_address[0]
        )

        if not _rate_ok(ip):
            log.warning("RATE_LIMIT ip=%s", ip)
            self._json(429, {"error": "Too many requests — try again later."})
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length)) if length else {}
        except json.JSONDecodeError:
            self._json(400, {"error": "Invalid JSON"})
            return

        machine_id = (body.get("machine_id") or "").strip().lower()

        if not machine_id:
            self._json(400, {"error": "machine_id is required"})
            return

        if not MACHINE_ID_RE.match(machine_id):
            self._json(400, {
                "error": "Invalid Machine ID. Run: selahpro --machine-id"
            })
            return

        key = _make_key(machine_id)
        ts  = datetime.now(timezone.utc).isoformat()
        log.info("KEYGEN machine_id=%s key=%s ip=%s ts=%s", machine_id, key, ip, ts)

        self._json(200, {
            "key":        key,
            "machine_id": machine_id,
            "product":    "SelahBridgePro",
            "issued":     ts,
        })

# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), KeygenHandler)
    log.info("SelahBridgePro keygen listening on 127.0.0.1:%d", PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Stopped")
