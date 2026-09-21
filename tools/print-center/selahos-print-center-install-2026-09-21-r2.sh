#!/usr/bin/env bash
# ============================================================
# selahos-print-center-install-2026-09-21-r2
#
# Adds the SelahOS Print Center to a SelahOS system you have ALREADY
# installed (Beta 2.0.1 or later) -- no reinstall needed.
#
#   bash selahos-print-center-install-2026-09-21-r2.sh            install / repair
#   bash selahos-print-center-install-2026-09-21-r2.sh --check    report only, changes nothing
#   bash selahos-print-center-install-2026-09-21-r2.sh --upgrade  full system update first (see below)
#   bash selahos-print-center-install-2026-09-21-r2.sh --extract DIR   just unpack the files to read them
#
# Run it as your normal user; it asks for your password (sudo) once.
# Safe to run twice.
#
# What it does:
#   1. Installs the printing packages: cups, cups-filters, cups-browsed, ghostscript, avahi, nss-mdns, print-manager, gutenprint, ipp-usb
#      (using a temporary copy of pacman.conf without [selahos-offline] and
#      [chaotic-aur], which break package installs on installed systems;
#      your real /etc/pacman.conf is never touched).
#   2. Installs two programs and a menu entry:
#        /usr/local/bin/selah-print               (the backend, also usable in a terminal)
#        /usr/local/bin/selahos-print-center      (the window)
#        /usr/share/applications/selahos-print-center.desktop
#   3. Sets up network printer discovery: printer .local names resolve
#      (mdns_minimal in /etc/nsswitch.conf), cups-browsed auto-adds AirPrint /
#      IPP Everywhere printers, and cups + avahi + cups-browsed are enabled.
#      Every system file it changes is first copied to /var/backups/selah-print/.
#
# Most printers made since about 2015 (AirPrint / "Mopria" / IPP Everywhere)
# need NO vendor driver. Older ones may need one; the Print Center tells you.
#
# --upgrade: Arch does not support installing new packages against an
# out-of-date package database. If step 1 says your database is out of date,
# re-run with --upgrade. It runs a full `pacman -Syu` first -- that updates
# everything on the system (it may rebuild DKMS drivers and want a reboot).
#
# Copyright (C) 2026 Selah Technologies LLC
# ============================================================
set -uo pipefail

VERSION="2026-09-21-r2"
DEST="${SELAH_PRINT_DESTDIR:-}"       # test hook: install under this root, no sudo/pacman/systemd

say()  { printf '%s\n' "$*"; }
ok()   { say "  [ok]      $*"; }
warn() { say "  [warning] $*"; }
bad()  { say "  [FAILED]  $*"; FAILED=$((FAILED+1)); }
FAILED=0

extract_payload() {
    local d="$1"
    mkdir -p "$d"
    payload_selah_print               > "$d/selah-print"
    payload_selahos_print_center      > "$d/selahos-print-center"
    payload_desktop_entry             > "$d/selahos-print-center.desktop"
    payload_print_txt                 > "$d/print.txt"
}

main() {
CHECK=0; UPGRADE=0; EXTRACT_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)    CHECK=1 ;;
        --upgrade)  UPGRADE=1 ;;
        --extract)  EXTRACT_DIR="${2:-}"; [ -n "$EXTRACT_DIR" ] || { echo "--extract needs a folder"; exit 1; }; shift ;;
        -h|--help)  awk 'NR>=3 && /^# ====/ {exit} NR>=3 {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        *) echo "Unknown option: $1  (try --help)"; exit 1 ;;
    esac
    shift
done


if [ -n "$EXTRACT_DIR" ]; then
    extract_payload "$EXTRACT_DIR"
    say "Unpacked to $EXTRACT_DIR:"; ls -1 "$EXTRACT_DIR"
    exit 0
fi

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"; TARGET_HOME="${TARGET_HOME:-$HOME}"
BIN="$DEST/usr/local/bin"; APPS="$DEST/usr/share/applications"; LISTS="$DEST/usr/local/share/selahos-install-packages"

# ---- --check: report only ----------------------------------------------
if [ "$CHECK" -eq 1 ]; then
    say "SelahOS Print Center installer $VERSION — check only (nothing will be changed)"; say
    for f in "$BIN/selah-print" "$BIN/selahos-print-center" "$APPS/selahos-print-center.desktop"; do
        [ -e "$f" ] && ok "present: ${f#"$DEST"}" || say "  [missing] ${f#"$DEST"}"
    done
    if [ -f "$BIN/selah-print" ]; then
        say; say "Printing setup status:"
        python3 "$BIN/selah-print" status --root "${DEST:-/}" | sed 's/^/  /'
    else
        say; say "Not installed yet. Run without --check to install."
    fi
    exit 0
fi

# ---- preflight -----------------------------------------------------------
say "SelahOS Print Center installer $VERSION"; say
if [ -z "$DEST" ]; then
    command -v pacman >/dev/null || { say "This needs a SelahOS / Arch-based system (pacman not found)."; exit 1; }
    command -v python3 >/dev/null || { say "python3 is required."; exit 1; }
fi
SUDO=""
if [ -z "$DEST" ] && [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null || { say "sudo is required (or run this as root)."; exit 1; }
    SUDO="sudo"
    say "You'll be asked for your password once."
    sudo -v || { say "Could not get administrator rights."; exit 1; }
fi

LOG="$TARGET_HOME/selahos-print-center-install.log"
{
say "Log: $LOG"; say

# ---- 1. files ----------------------------------------------------------------
say "1/3  Installing the Print Center files"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
extract_payload "$TMP"
if python3 -m py_compile "$TMP/selah-print" "$TMP/selahos-print-center" 2>/dev/null; then
    ok "files unpacked and verified"
else
    bad "unpacked files are damaged — download the script again"; exit 1
fi
$SUDO install -Dm755 "$TMP/selah-print"                       "$BIN/selah-print"                                && ok "${BIN#"$DEST"}/selah-print"               || bad "selah-print"
$SUDO install -Dm755 "$TMP/selahos-print-center"              "$BIN/selahos-print-center"                       && ok "${BIN#"$DEST"}/selahos-print-center"      || bad "selahos-print-center"
$SUDO install -Dm644 "$TMP/selahos-print-center.desktop"      "$APPS/selahos-print-center.desktop"              && ok "menu entry"                                || bad "menu entry"
$SUDO install -Dm644 "$TMP/print.txt"                         "$LISTS/print.txt"                                && ok "package list"                              || bad "package list"

# ---- 2. packages + network discovery + services -------------------------------
say; say "2/3  Installing printing packages and setting up network printer discovery"
if [ -n "$DEST" ]; then
    python3 "$BIN/selah-print" configure --root "$DEST" || FAILED=$((FAILED+1))
else
    UPG=(); [ "$UPGRADE" -eq 1 ] && UPG=(--upgrade)
    $SUDO python3 /usr/local/bin/selah-print configure --install-missing --now "${UPG[@]}" || FAILED=$((FAILED+1))
fi

# ---- 3. verify --------------------------------------------------------------------
say; say "3/3  Checking the result"
STATUS_OUT="$(python3 "$BIN/selah-print" status --root "${DEST:-/}")"
printf '%s\n' "$STATUS_OUT" | sed 's/^/  /'
# A FAIL in the final check is a real problem even when every step above said OK.
# (2026-09-21: the first real run printed "Done." right under a FAIL line.)
FAILED=$((FAILED + $(printf '%s\n' "$STATUS_OUT" | grep -c '^[[:space:]]*FAIL')))

if [ -z "$DEST" ]; then
    case " $(id -nG "$TARGET_USER" 2>/dev/null) " in
        *" wheel "*|*" sys "*) ok "$TARGET_USER can manage printers (wheel/sys group)" ;;
        *) warn "$TARGET_USER is not in the wheel or sys group, so adding printers will be refused." ;;
    esac
    # refresh the KDE menu so the new entry shows without logging out
    for k in kbuildsycoca6 kbuildsycoca5; do
        if command -v "$k" >/dev/null; then
            if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != root ]; then sudo -u "$TARGET_USER" "$k" --noincremental >/dev/null 2>&1
            else "$k" --noincremental >/dev/null 2>&1; fi
            break
        fi
    done
    say; say "Looking for printers on your network..."
    if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != root ]; then sudo -u "$TARGET_USER" python3 /usr/local/bin/selah-print discover
    else python3 /usr/local/bin/selah-print discover; fi
fi

say
if [ "$FAILED" -eq 0 ]; then
    say "Done. Open the Print Center from the application menu (search \"Print Center\"),"
    say "or run:  selahos-print-center"
    say "Printers you add there show up in every app's Print dialog."
else
    say "Finished with $FAILED problem(s) — see [FAILED]/FAIL lines above and the log: $LOG"
    say "If it mentions an out-of-date package database, run this script again with --upgrade."
fi
} 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
}

# ============================ payload ============================
# The files below are the exact program sources this script installs.
# Read them here, or unpack them without installing:  --extract DIR

payload_selah_print() {
cat <<'__SELAH_PAYLOAD_PAYLOAD_SELAH_PRINT__'
#!/usr/bin/env python3
# ============================================================
# selah-print — SelahOS printer discovery & setup backend
#
# Everything the Print Center GUI (selahos-print-center) does goes through
# this tool, so it is also usable from a terminal, from selah-repair, and
# from the installer. Pure standard library; talks to CUPS by running the
# stock lpadmin/lpstat/lpoptions/lp/cancel commands.
#
# Design notes (2026-09-21, first cut, tested against a real Brother
# HL-L3230CDW on the dev VM's LAN):
#   * Discovery is our own dependency-free mDNS query, NOT avahi-browse:
#     it works before avahi-daemon is up, on the live ISO, and can be
#     tested without root. It asks on every LAN interface.
#   * Modern network printers (AirPrint / IPP Everywhere -- essentially
#     everything sold since ~2015) need NO vendor driver: CUPS builds the
#     queue from the printer's own IPP attributes (`lpadmin -m everywhere`).
#     Older printers fall back to a PPD search (brlaser, gutenprint, ...).
#   * Queues are created unshared (printer-is-shared=false).
#   * `configure` is the one-shot system setup (nss-mdns, cups-browsed
#     policy, services). It is idempotent and safe to re-run; the live ISO
#     build, the installer and the Print Center "Repair" button all use it.
#
# Usage:
#   selah-print discover [--json] [--timeout N]
#   selah-print probe HOST_OR_URI [--json]
#   selah-print list [--json]
#   selah-print add HOST_OR_URI [--name N] [--driver auto|everywhere|<ppd>] [--default] [--json]
#   selah-print remove NAME | default NAME | test-page NAME
#   selah-print jobs [NAME] [--json] | cancel JOBID | cancel-all NAME
#   selah-print options NAME [--set KEY=VALUE ...] [--json]
#   selah-print status [--json]                      (exit 0 ok, 2 problems)
#   selah-print configure [--root DIR] [--now] [--install-missing] [--upgrade]   (root)
#
# Copyright (C) 2026 Selah Technologies LLC
# ============================================================

import argparse
import concurrent.futures
import http.client
import json
import os
import re
import select
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import time

CHILD_ENV = dict(os.environ, LC_ALL='C', LANG='C')

PKGLIST = '/usr/local/share/selahos-install-packages/print.txt'
# Used only when print.txt is not on disk (e.g. repairing an old install).
FALLBACK_PACKAGES = ['cups', 'cups-filters', 'cups-browsed', 'ghostscript',
                     'avahi', 'nss-mdns', 'print-manager']
REQUIRED_PACKAGES = ['cups', 'cups-filters', 'cups-browsed', 'ghostscript',
                     'avahi', 'nss-mdns']
SERVICES = ['avahi-daemon.service', 'cups.service', 'cups-browsed.service']


# ── helpers ──────────────────────────────────────────────────────────────

def run(cmd, timeout=20, stdin=None):
    """Run a command; never raises. Returns (returncode, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           env=CHILD_ENV, input=stdin)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, '', f'{cmd[0]}: command not found'
    except subprocess.TimeoutExpired:
        return 124, '', f'{cmd[0]}: timed out after {timeout}s'


def emit(obj, as_json):
    if as_json:
        print(json.dumps(obj, indent=2))
    return obj


def die(msg, as_json=False, code=1, **extra):
    if as_json:
        print(json.dumps(dict(ok=False, error=msg, **extra)))
    else:
        print(f'selah-print: {msg}', file=sys.stderr)
    sys.exit(code)


def cups_error(err):
    """Boil lpadmin/lp stderr down to something a person can read."""
    err = (err or '').strip()
    if 'Forbidden' in err or 'Unauthorized' in err or 'authentication' in err.lower():
        return ('CUPS refused the change: this account is not a printer '
                'administrator (must be in the wheel or sys group).')
    if 'cupsd' in err and ('not running' in err or 'Connection refused' in err):
        return 'The print service (cups) is not running.'
    if 'Bad Request' in err or 'Not Found' in err:
        return err.splitlines()[-1] if err else 'CUPS rejected the request.'
    return err.splitlines()[-1] if err else 'Unknown CUPS error.'


# ── minimal mDNS (DNS-SD) discovery ──────────────────────────────────────

MDNS_GROUP = ('224.0.0.251', 5353)
MDNS_SERVICES = ('_ipp._tcp', '_ipps._tcp', '_printer._tcp', '_pdl-datastream._tcp')
_SKIP_IFACE = re.compile(r'^(tailscale|docker|br-|veth|virbr|tun|wg|zt|lo$)')


def _qname(name):
    return b''.join(bytes([len(p)]) + p.encode() for p in name.strip('.').split('.')) + b'\0'


def _mdns_query(names):
    # QU bit (0x8000) asks responders to answer by unicast to our ephemeral
    # port, so we never need to bind :5353 (which avahi already owns).
    q = b''.join(_qname(n) + struct.pack('>HH', 12, 0x8001) for n in names)
    return struct.pack('>HHHHHH', 0, 0, len(names), 0, 0, 0) + q


def _dns_name(d, o):
    parts, jumped, end, hops = [], False, o, 0
    while True:
        n = d[o]
        if n == 0:
            o += 1
            break
        if n & 0xC0 == 0xC0:
            hops += 1
            if hops > 20:
                raise ValueError('dns compression loop')
            ptr = ((n & 0x3F) << 8) | d[o + 1]
            if not jumped:
                end = o + 2
            jumped, o = True, ptr
            continue
        parts.append(d[o + 1:o + 1 + n].decode('utf8', 'replace'))
        o += 1 + n
    return '.'.join(parts), (end if jumped else o)


def _mdns_parse(d):
    _, _, qd, an, ns, ar = struct.unpack('>HHHHHH', d[:12])
    o = 12
    for _ in range(qd):
        _, o = _dns_name(d, o)
        o += 4
    recs = []
    for _ in range(an + ns + ar):
        name, o = _dns_name(d, o)
        rtype, _, _, rdlen = struct.unpack('>HHIH', d[o:o + 10])
        o += 10
        rd = d[o:o + rdlen]
        val = None
        if rtype == 12:
            val = _dns_name(d, o)[0]
        elif rtype == 33:
            port = struct.unpack('>H', rd[4:6])[0]
            val = (_dns_name(d, o + 6)[0], port)
        elif rtype == 16:
            val, i = {}, 0
            while i < len(rd):
                ln = rd[i]
                kv = rd[i + 1:i + 1 + ln].decode('utf8', 'replace')
                k, _, v = kv.partition('=')
                if k:
                    val[k.lower()] = v
                i += 1 + ln
        elif rtype == 1:
            val = socket.inet_ntoa(rd)
        recs.append((name, rtype, val))
        o += rdlen
    return recs


def _local_ipv4s():
    rc, out, _ = run(['ip', '-4', '-o', 'addr', 'show', 'scope', 'global'], timeout=5)
    ips = []
    for line in out.splitlines():
        m = re.match(r'\d+:\s+(\S+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)', line)
        if not m:
            continue
        ifname, ip, plen = m.groups()
        if int(plen) >= 32 or _SKIP_IFACE.match(ifname):
            continue
        ips.append(ip)
    return ips or ['']            # '' = let the kernel choose the interface


def mdns_scan(timeout=4.0):
    socks = []
    for ip in _local_ipv4s():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((ip, 0))
            s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
            if ip:
                s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
            socks.append(s)
        except OSError:
            continue
    if not socks:
        return []
    pkt = _mdns_query([f'{t}.local' for t in MDNS_SERVICES])
    records, sent, next_send = [], 0, 0.0
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        now = time.monotonic()
        if sent < 2 and now >= next_send:
            for s in socks:
                try:
                    s.sendto(pkt, MDNS_GROUP)
                except OSError:
                    pass
            sent += 1
            next_send = now + 1.0
        ready, _, _ = select.select(socks, [], [], 0.25)
        for s in ready:
            try:
                data, addr = s.recvfrom(9000)
                records.extend((addr[0],) + r for r in _mdns_parse(data))
            except (OSError, ValueError, IndexError, struct.error):
                continue
    for s in socks:
        s.close()
    return _group_services(records)


def _group_services(records):
    """records: (src_ip, name, rtype, value) -> one entry per printer."""
    a_rec = {n.lower(): v for _, n, t, v in records if t == 1}
    entries = {}
    for src, name, rtype, val in records:
        if rtype not in (33, 16):
            continue
        m = re.match(r'^(.*)\.(_[a-z-]+\._tcp)\.local$', name, re.I)
        if not m or m.group(2).lower() not in MDNS_SERVICES:
            continue
        label, svc = m.group(1), m.group(2).lower()
        e = entries.setdefault((src, label), dict(
            name=label, ip=src, host=None, services={}, txt={}))
        s = e['services'].setdefault(svc, dict(port=None, txt={}))
        if rtype == 33:
            s['port'] = val[1]
            e['host'] = e['host'] or val[0]
            if val[0].lower() in a_rec:
                e['ip'] = a_rec[val[0].lower()]
        else:
            s['txt'].update(val)
    out = []
    for e in entries.values():
        for svc in ('_ipps._tcp', '_ipp._tcp', '_printer._tcp', '_pdl-datastream._tcp'):
            e['txt'].update(e['services'].get(svc, {}).get('txt', {}))
        out.append(e)
    return sorted(out, key=lambda e: e['name'].lower())


# ── minimal IPP client (read-only Get-Printer-Attributes) ────────────────

IPP_WANT = ['printer-name', 'printer-make-and-model', 'printer-info',
            'printer-state', 'printer-state-reasons', 'printer-is-accepting-jobs',
            'document-format-supported', 'ipp-versions-supported', 'color-supported',
            'sides-supported', 'printer-device-id', 'printer-uuid',
            'marker-names', 'marker-levels', 'marker-colors', 'marker-types']


def _ipp_attr(tag, name, val):
    return bytes([tag]) + struct.pack('>H', len(name)) + name.encode() + struct.pack('>H', len(val)) + val


def _ipp_request(uri):
    r = struct.pack('>BBHI', 2, 0, 0x000B, 1) + b'\x01'
    r += _ipp_attr(0x47, 'attributes-charset', b'utf-8')
    r += _ipp_attr(0x48, 'attributes-natural-language', b'en')
    r += _ipp_attr(0x45, 'printer-uri', uri.encode())
    r += _ipp_attr(0x44, 'requested-attributes', IPP_WANT[0].encode())
    for w in IPP_WANT[1:]:
        r += _ipp_attr(0x44, '', w.encode())
    return r + b'\x03'


def _ipp_value(tag, v):
    if tag in (0x21, 0x23) and len(v) == 4:
        return struct.unpack('>i', v)[0]
    if tag == 0x22:
        return bool(v[0]) if v else False
    return v.decode('utf8', 'replace')


def _ipp_parse(d):
    status = struct.unpack('>H', d[2:4])[0]
    out, o, cur, depth = {}, 8, None, 0
    while o < len(d):
        t = d[o]
        o += 1
        if t <= 0x0F:                       # delimiter tag
            if t == 0x03:
                break
            cur = None
            continue
        nl = struct.unpack('>H', d[o:o + 2])[0]
        name = d[o + 2:o + 2 + nl].decode('utf8', 'replace')
        o += 2 + nl
        vl = struct.unpack('>H', d[o:o + 2])[0]
        v = d[o + 2:o + 2 + vl]
        o += 2 + vl
        if t == 0x34:                       # begCollection: skip its members
            depth += 1
            continue
        if t == 0x37:
            depth = max(0, depth - 1)
            continue
        if depth or t == 0x4A:
            continue
        if nl:
            cur = name
        if cur is not None:
            out.setdefault(cur, []).append(_ipp_value(t, v))
    return status, out


def ipp_get_attributes(host, port=631, path='/ipp/print', tls=False, timeout=3.0):
    """Returns the attribute dict, or None if the printer does not answer IPP here."""
    uri = f"{'ipps' if tls else 'ipp'}://{host}:{port}{path}"
    conn = None
    try:
        if tls:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False          # printers ship self-signed certs; read-only query
            ctx.verify_mode = ssl.CERT_NONE
            conn = http.client.HTTPSConnection(host, port, timeout=timeout, context=ctx)
        else:
            conn = http.client.HTTPConnection(host, port, timeout=timeout)
        conn.request('POST', path, _ipp_request(uri), {'Content-Type': 'application/ipp'})
        resp = conn.getresponse()
        body = resp.read()
        if resp.status != 200 or len(body) < 8:
            return None
        status, attrs = _ipp_parse(body)
        return attrs if status < 0x0100 else None
    except (OSError, http.client.HTTPException, struct.error, ValueError, IndexError):
        return None
    finally:
        if conn:
            conn.close()


def _first(attrs, key, default=''):
    v = attrs.get(key)
    return v[0] if v else default


def summarize_ipp(attrs, host, port, path, tls):
    formats = attrs.get('document-format-supported', [])
    versions = attrs.get('ipp-versions-supported', [])
    try:
        best = max(float(v) for v in versions)
    except ValueError:
        best = 0.0
    everywhere = best >= 2.0 and any(f in formats for f in
                                     ('image/urf', 'image/pwg-raster', 'application/pdf'))
    markers = []
    names = attrs.get('marker-names', [])
    levels = attrs.get('marker-levels', [])
    colors = attrs.get('marker-colors', [])
    for i, n in enumerate(names):
        lvl = levels[i] if i < len(levels) and isinstance(levels[i], int) else -1
        markers.append(dict(name=n, level=lvl if 0 <= lvl <= 100 else None,
                            color=colors[i] if i < len(colors) and colors[i].startswith('#') else None))
    return dict(
        uri=f"{'ipps' if tls else 'ipp'}://{host}{'' if port == 631 else f':{port}'}{path}",
        model=_first(attrs, 'printer-make-and-model') or _first(attrs, 'printer-info'),
        color=bool(_first(attrs, 'color-supported', False)),
        duplex=any(s.startswith('two-sided') for s in attrs.get('sides-supported', [])),
        accepting=bool(_first(attrs, 'printer-is-accepting-jobs', True)),
        reasons=[r for r in attrs.get('printer-state-reasons', []) if r != 'none'],
        formats=formats, ipp_version=best, everywhere=everywhere,
        device_id=_first(attrs, 'printer-device-id'), markers=markers)


def probe_ipp(host, port=None, paths=None, timeout=3.0):
    """Find the working IPP endpoint on host. Returns summary dict or None."""
    combos = []
    for p in (paths or []) + ['/ipp/print', '/ipp', '/ipp/printer']:
        p = p if p.startswith('/') else '/' + p
        for prt, tls in ([(port, port == 443)] if port else [(631, False), (443, True)]):
            if (prt, tls, p) not in combos:
                combos.append((prt, tls, p))
    for prt, tls, p in combos:
        attrs = ipp_get_attributes(host, prt, p, tls, timeout)
        if attrs:
            return summarize_ipp(attrs, host, prt, p, tls)
    return None


# ── CUPS queries ─────────────────────────────────────────────────────────

def _host_of(uri):
    m = re.match(r'^(?:ipps?|https?|socket|lpd)://(?:[^@/]*@)?(\[[^\]]+\]|[^:/]+)', uri or '')
    return m.group(1).strip('[]') if m else None


def _resolves(host):
    try:
        socket.getaddrinfo(host, 631, socket.AF_INET)
        return True
    except OSError:
        return False


def list_queues(with_markers=True):
    rc, out, err = run(['lpstat', '-r'], timeout=8)
    if rc == 127:
        return dict(ok=False, error='CUPS is not installed (run Repair in the Print Center).', printers=[])
    if rc != 0 or 'not running' in out:
        return dict(ok=False, error='The print service (cups) is not running.', printers=[])
    default = None
    rc, out, _ = run(['lpstat', '-d'], timeout=8)
    m = re.search(r'destination:\s*(\S+)', out)
    if m:
        default = m.group(1)
    uris = {}
    rc, out, _ = run(['lpstat', '-v'], timeout=8)
    for line in out.splitlines():
        m = re.match(r'device for (\S+):\s*(.*)$', line)
        if m:
            uris[m.group(1)] = m.group(2).strip()
    jobs_by = {}
    rc, out, _ = run(['lpstat', '-o'], timeout=8)
    for line in out.splitlines():
        m = re.match(r'^(\S+)-\d+\s', line)
        if m:
            jobs_by[m.group(1)] = jobs_by.get(m.group(1), 0) + 1
    printers = []
    rc, out, _ = run(['lpstat', '-l', '-p'], timeout=10)
    cur = None
    for line in out.splitlines():
        m = re.match(r'^printer (\S+) (.*)$', line)
        if m:
            cur = dict(name=m.group(1), state_text=m.group(2).strip(), description='',
                       location='', alerts=[])
            printers.append(cur)
            continue
        if cur and line.startswith(('\t', ' ')):
            k, _, v = line.strip().partition(':')
            v = v.strip()
            if k == 'Description':
                cur['description'] = v
            elif k == 'Location':
                cur['location'] = v
            elif k == 'Alerts' and v and v != 'none':
                cur['alerts'] = v.split()
    for p in printers:
        st = p['state_text'].lower()
        if 'disabled' in st:
            p['state'] = 'stopped'
        elif 'now printing' in st or 'processing' in st:
            p['state'] = 'printing'
        else:
            p['state'] = 'idle'
        p['uri'] = uris.get(p['name'], '')
        p['host'] = _host_of(p['uri'])
        p['default'] = (p['name'] == default)
        p['jobs'] = jobs_by.get(p['name'], 0)
        rc, o2, _ = run(['lpoptions', '-p', p['name']], timeout=6)
        p['auto'] = 'cups-browsed=true' in o2
        p['shared'] = 'printer-is-shared=true' in o2
        m = re.search(r"printer-make-and-model='([^']*)'", o2)
        p['model'] = re.sub(r'\s+-\s+IPP Everywhere$', '', m.group(1)) if m else ''
        p['markers'] = []
    if with_markers:
        def fetch(p):
            if p['host'] and p['uri'].startswith(('ipp', 'http')):
                info = probe_ipp(p['host'], timeout=2.0)
                if info:
                    p['markers'] = info['markers']
                    p['reachable'] = True
                    return
                p['reachable'] = False
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
            list(ex.map(fetch, printers))
    return dict(ok=True, default=default, printers=printers)


# ── discovery ────────────────────────────────────────────────────────────

def discover(timeout=4.0):
    found = mdns_scan(timeout)
    existing = list_queues(with_markers=False).get('printers', [])
    have_hosts = {p['host'].lower() for p in existing if p.get('host')}

    def enrich(e):
        ipp = e['services'].get('_ipp._tcp') or e['services'].get('_ipps._tcp')
        tls = '_ipps._tcp' in e['services'] and '_ipp._tcp' not in e['services']
        probe = None
        if ipp:
            rp = ipp['txt'].get('rp', '')      # the IPP record's own rp; _printer's rp is an LPD queue name
            probe = probe_ipp(e['ip'], ipp['port'] or (443 if tls else 631),
                              paths=[rp] if rp else None)
        model = (probe or {}).get('model') or e['txt'].get('ty') or e['txt'].get('product', '').strip('()') or e['name']
        proto = 'ipp' if probe else ('socket' if '_pdl-datastream._tcp' in e['services']
                                     else 'lpd' if '_printer._tcp' in e['services'] else None)
        hostnames = {e['ip'].lower()} | ({e['host'].lower().rstrip('.')} if e['host'] else set())
        return dict(
            name=e['name'], model=model, ip=e['ip'], host=e['host'],
            protocol=proto,
            driver='driverless' if probe and probe['everywhere'] else 'needs-driver',
            color=(probe or {}).get('color', e['txt'].get('color', '').upper() == 'T'),
            duplex=(probe or {}).get('duplex', e['txt'].get('duplex', '').upper() == 'T'),
            uri=(probe or {}).get('uri'),
            markers=(probe or {}).get('markers', []),
            already_added=bool(hostnames & have_hosts),
            ready=proto is not None)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(enrich, found))
    return [r for r in results if r['ready']]


# ── adding printers ──────────────────────────────────────────────────────

def _norm(s):
    s = re.sub(r'\bseries\b', '', (s or '').lower())
    return re.sub(r'[^a-z0-9]', '', s)


def find_drivers(model, make=''):
    """PPD candidates for an older printer, best first."""
    rc, out, _ = run(['lpinfo', '-m'], timeout=90)
    want = _norm(model)
    if rc != 0 or len(want) < 3:
        return []
    ranked = []
    for line in out.splitlines():
        ppd, _, desc = line.partition(' ')
        if ppd in ('raw', 'everywhere') or 'generic' in desc.lower():
            continue
        if want in _norm(desc):
            family = ('brlaser' if 'brlaser' in ppd else
                      'gutenprint' if 'gutenprint' in ppd.lower() or 'gutenprint' in desc.lower() else
                      'hplip' if ppd.startswith('hplip') else
                      'splix' if 'splix' in ppd or 'samsung' in ppd.lower() else 'other')
            pref = {'brlaser': 0, 'hplip': 1, 'splix': 2, 'other': 3, 'gutenprint': 4}[family]
            ranked.append((pref, len(desc), ppd, desc.strip(), family))
    ranked.sort()
    return [dict(ppd=r[2], description=r[3], family=r[4]) for r in ranked[:8]]


def _port_open(host, port, timeout=2.5):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _queue_name(model, taken):
    base = re.sub(r'[^A-Za-z0-9]+', '_', re.sub(r'\bseries\b', '', model or 'Printer', flags=re.I)).strip('_') or 'Printer'
    name, n = base, 2
    while name in taken:
        name, n = f'{base}_{n}', n + 1
    return name


def add_printer(target, name=None, driver='auto', make_default=False):
    q = list_queues(with_markers=False)
    if not q['ok']:
        return dict(ok=False, error=q['error'])
    taken = {p['name'] for p in q['printers']}
    uri, model, info, hostkey = None, None, None, None

    if '://' in target:
        uri = target
        hostkey = _host_of(uri)
        if uri.startswith(('ipp://', 'ipps://')) and hostkey:
            m = re.match(r'^ipps?://[^/:]+(?::(\d+))?(/.*)?$', uri)
            info = probe_ipp(hostkey, int(m.group(1)) if m and m.group(1) else None,
                             paths=[m.group(2)] if m and m.group(2) else None)
    else:
        hostkey = target
        if not re.match(r'^[A-Za-z0-9._:-]+$', target):
            return dict(ok=False, error="That doesn't look like a printer address. "
                                        "Use an IP address (192.168.1.50) or a name (printer.local).")
        info = probe_ipp(target)
        if info:
            uri = info['uri']
        elif _port_open(target, 9100):
            uri = f'socket://{target}:9100'       # raw JetDirect: driver chosen by model below
        else:
            return dict(ok=False, unreachable=True,
                        error=f"Couldn't reach a printer at {target}. Check the address, and that the "
                              "printer is turned on and connected to this network.")

    # Prefer the stable .local name over a DHCP address when mDNS resolves it,
    # and remember every name this printer is known by for duplicate detection.
    hostkeys = {hostkey.lower()} if hostkey else set()
    if '://' not in target:
        for e in mdns_scan(3.0):
            if e['ip'] == target and e['host']:
                mdns_name = e['host'].rstrip('.')
                hostkeys.add(mdns_name.lower())
                if _resolves(mdns_name):
                    uri = uri.replace(target, mdns_name, 1)
                break

    for p in q['printers']:
        if p.get('host') and p['host'].lower() in hostkeys:
            return dict(ok=True, name=p['name'], note='already-added', uri=p['uri'],
                        driver='existing')

    model = (info or {}).get('model') or ''
    qname = name or _queue_name(model, taken)
    if not re.match(r'^[A-Za-z0-9_.-]+$', qname):
        return dict(ok=False, error='Printer names may only contain letters, numbers, _ . and -')
    if qname in taken:
        return dict(ok=False, error=f'A printer named {qname} already exists.')
    desc = (model or qname).strip()
    base = ['lpadmin', '-p', qname, '-E', '-v', uri, '-D', desc, '-o', 'printer-is-shared=false']

    # Driver plan, best first: the printer's own IPP Everywhere description,
    # then (older printers) the best PPD match, or whatever the caller named.
    tried, plan = [], []
    if driver == 'everywhere' or (driver == 'auto' and info and info['everywhere']):
        plan.append(('everywhere', 'driverless (IPP Everywhere)'))
    elif driver != 'auto':
        plan.append((driver, driver))
    if driver == 'auto':
        cands = find_drivers(model or target)
        if cands:
            plan.append((cands[0]['ppd'], f"{cands[0]['family']}: {cands[0]['description']}"))
    err = ''
    for ppd, label in plan:
        rc, _, e = run(base + ['-m', ppd], timeout=60)
        tried.append(label)
        if rc == 0:
            if make_default or not q['default']:
                run(['lpadmin', '-d', qname], timeout=10)
            return dict(ok=True, name=qname, uri=uri, driver=label,
                        model=model, default=bool(make_default or not q['default']))
        err = cups_error(e)
        run(['lpadmin', '-x', qname], timeout=10)   # don't leave a half-made queue

    if not plan:
        return dict(ok=False, error='No driver found for this printer.', needs_driver=True,
                    model=model or target,
                    hint=('SelahOS could not find a matching driver for '
                          f'"{model or target}". Try the maker\'s website for a Linux driver, '
                          'or add it with a generic driver from the Print Center.'))
    return dict(ok=False, error=err or 'CUPS could not create the printer.', tried=tried)


# ── queue management ─────────────────────────────────────────────────────

def simple(cmd, ok_msg, timeout=20):
    rc, out, err = run(cmd, timeout=timeout)
    if rc == 0:
        return dict(ok=True, message=ok_msg, output=out.strip())
    return dict(ok=False, error=cups_error(err or out))


def test_page(name):
    data = os.environ.get('CUPS_DATADIR', '/usr/share/cups')
    page = os.path.join(data, 'data', 'default-testpage.pdf')
    if not os.path.exists(page):
        return dict(ok=False, error='CUPS test page file is missing.')
    rc, out, err = run(['lp', '-d', name, '-t', 'SelahOS test page', page], timeout=20)
    if rc != 0:
        return dict(ok=False, error=cups_error(err))
    m = re.search(r'request id is (\S+)', out)
    return dict(ok=True, job=m.group(1) if m else None)


def list_jobs(name=None):
    cmd = ['lpstat', '-o'] + ([name] if name else [])
    rc, out, err = run(cmd, timeout=10)
    jobs = []
    for line in out.splitlines():
        m = re.match(r'^(\S+)-(\d+)\s+(\S+)\s+(\d+)\s+(.*)$', line)
        if m:
            jobs.append(dict(id=f'{m.group(1)}-{m.group(2)}', printer=m.group(1),
                             user=m.group(3), size=int(m.group(4)), when=m.group(5).strip()))
    return dict(ok=True, jobs=jobs)


OPTION_KEYS = ('Duplex', 'ColorModel', 'PageSize', 'MediaType', 'InputSlot')


def _options_from_ppd(name):
    """Fallback when `lpoptions -l` cannot fetch the PPD: read the queue's PPD file."""
    root = os.environ.get('CUPS_SERVERROOT', '/etc/cups')
    txt = _read(os.path.join(root, 'ppd', f'{name}.ppd'))
    if not txt:
        return None
    opts = []
    for key in OPTION_KEYS:
        m = re.search(rf'^\*OpenUI \*{key}/([^:]*):', txt, re.M)
        if not m:
            continue
        choices = re.findall(rf'^\*{key} ([^/:\s]+)[^:]*:', txt, re.M)
        d = re.search(rf'^\*Default{key}:\s*(\S+)', txt, re.M)
        opts.append(dict(key=key, label=m.group(1).strip(),
                         choices=[c for c in choices if not c.startswith('Custom')],
                         default=d.group(1) if d else None))
    return opts


def get_options(name):
    rc, out, err = run(['lpoptions', '-p', name, '-l'], timeout=10)
    opts = []
    if rc == 0 and out.strip():
        for line in out.splitlines():
            m = re.match(r'^([^/:]+)/([^:]*):\s*(.*)$', line)
            if not m or m.group(1) not in OPTION_KEYS:
                continue
            choices = m.group(3).split()
            default = next((c[1:] for c in choices if c.startswith('*')), None)
            opts.append(dict(key=m.group(1), label=m.group(2).strip(),
                             choices=[c.lstrip('*') for c in choices if not c.startswith('Custom.')],
                             default=default))
    else:
        opts = _options_from_ppd(name)
    if not opts:
        return dict(ok=False, error='Printer options are not available for this printer.')
    return dict(ok=True, options=opts)


def set_option(name, key, value):
    if not re.match(r'^[A-Za-z0-9_.-]+$', key) or not re.match(r'^[A-Za-z0-9_.-]+$', value):
        return dict(ok=False, error='Invalid option.')
    return simple(['lpadmin', '-p', name, '-o', f'{key}={value}'], 'Option saved.')


# ── system configuration (root) ──────────────────────────────────────────

BROWSED_MARKER = '# --- SelahOS (selah-print configure)'
BROWSED_KEYS = {'BrowseRemoteProtocols': 'dnssd', 'CreateIPPPrinterQueues': 'Driverless',
                'NewIPPPrinterQueuesShared': 'No'}


def pkg_installed(pkg, root='/'):
    cmd = ['pacman', '-Qq', pkg] if root == '/' else ['pacman', '-r', root, '-Qq', pkg]
    return run(cmd, timeout=15)[0] == 0


def wanted_packages():
    try:
        with open(PKGLIST) as f:
            pk = [l.split('#', 1)[0].strip() for l in f]
        pk = [p for p in pk if p]
        if pk:
            return pk
    except OSError:
        pass
    return FALLBACK_PACKAGES


def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def nsswitch_ok(root='/'):
    txt = _read(os.path.join(root, 'etc/nsswitch.conf')) or ''
    return any(l.startswith('hosts:') and 'mdns' in l for l in txt.splitlines())


def browsed_ok(root='/'):
    txt = _read(os.path.join(root, 'etc/cups/cups-browsed.conf')) or ''
    active = {}
    for l in txt.splitlines():
        if l.strip() and not l.lstrip().startswith('#'):
            k, _, v = l.strip().partition(' ')
            active[k] = v.strip()
    return all(active.get(k, '').lower() == v.lower() for k, v in BROWSED_KEYS.items())


def systemgroup_ok(root='/'):
    txt = _read(os.path.join(root, 'etc/cups/cups-files.conf')) or ''
    m = re.search(r'^SystemGroup\s+(.*)$', txt, re.M)
    return bool(m and ('wheel' in m.group(1).split() or 'sys' in m.group(1).split()))


def unit_exists(unit, root='/'):
    return any(os.path.exists(os.path.join(root, d, unit))
               for d in ('usr/lib/systemd/system', 'etc/systemd/system', 'lib/systemd/system'))


def svc_state(unit, root='/'):
    if root != '/':
        return dict(enabled=None, active=None)
    e = run(['systemctl', 'is-enabled', unit], timeout=8)[1].strip()
    a = run(['systemctl', 'is-active', unit], timeout=8)[1].strip()
    return dict(enabled=e in ('enabled', 'static', 'alias'), active=(a == 'active'))


def status(root='/'):
    checks = []

    def add(cid, label, ok, detail='', fatal=True):
        checks.append(dict(id=cid, label=label, ok=bool(ok), detail=detail, fatal=fatal))

    for pkg in REQUIRED_PACKAGES:
        add(f'pkg-{pkg}', f'{pkg} installed', pkg_installed(pkg, root))
    add('pkg-print-manager', 'KDE Printers settings (print-manager) installed',
        pkg_installed('print-manager', root), fatal=False)
    add('nsswitch', 'Network name lookup can resolve printer .local names (nss-mdns)',
        nsswitch_ok(root), '/etc/nsswitch.conf hosts: line needs mdns_minimal')
    add('browsed-conf', 'cups-browsed set to auto-add driverless network printers',
        browsed_ok(root), '/etc/cups/cups-browsed.conf')
    add('systemgroup', 'CUPS lets this desktop\'s admin group manage printers',
        systemgroup_ok(root), 'SystemGroup in /etc/cups/cups-files.conf')
    for unit in SERVICES:
        if not unit_exists(unit, root):
            add(f'svc-{unit}', f'{unit} present', False, 'unit file missing (package not installed?)')
            continue
        st = svc_state(unit, root)
        if root == '/':
            add(f'svc-{unit}', f'{unit} enabled', st['enabled'])
        else:
            # lexists: the symlink targets are root-relative, so following them
            # would resolve against the HOST filesystem instead of `root`.
            enabled = os.path.lexists(os.path.join(root, 'etc/systemd/system/multi-user.target.wants', unit)) or \
                os.path.lexists(os.path.join(root, 'etc/systemd/system/printer.target.wants', unit))
            add(f'svc-{unit}', f'{unit} enabled', enabled)
    return dict(ok=all(c['ok'] for c in checks if c['fatal']), checks=checks)


def _backup(root, path):
    """Copy a system file to <root>/var/backups/selah-print/ before we change it."""
    import shutil
    dest = os.path.join(root, 'var/backups/selah-print')
    os.makedirs(dest, exist_ok=True)
    shutil.copy2(path, os.path.join(dest, os.path.basename(path) + '.' + time.strftime('%Y%m%d-%H%M%S')))


def _patch_nsswitch(root):
    path = os.path.join(root, 'etc/nsswitch.conf')
    txt = _read(path)
    if txt is None:
        return 'nsswitch.conf missing'
    lines, changed = [], False
    for l in txt.splitlines():
        if l.startswith('hosts:') and 'mdns' not in l:
            tok = l.split()
            marker = ['mdns_minimal', '[NOTFOUND=return]']
            for anchor in ('resolve', 'files', 'dns'):
                if anchor in tok:
                    i = tok.index(anchor)
                    tok[i:i] = marker
                    break
            else:
                tok += marker
            l, changed = ' '.join(tok), True
        lines.append(l)
    if changed:
        _backup(root, path)
        with open(path, 'w') as f:
            f.write('\n'.join(lines) + '\n')
    return 'patched' if changed else 'already ok'


def _patch_browsed(root):
    path = os.path.join(root, 'etc/cups/cups-browsed.conf')
    txt = _read(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kept, skipping = [], False
    for l in (txt or '').splitlines():
        if l.startswith(BROWSED_MARKER):
            skipping = True                         # drop our previous block; re-added below
            continue
        if skipping:
            k = l.split(None, 1)[0] if l.strip() else ''
            if not l.strip() or l.lstrip().startswith('#') or k in BROWSED_KEYS:
                continue
            skipping = False
        if l.split(None, 1)[:1] and l.split(None, 1)[0] in BROWSED_KEYS and not l.lstrip().startswith('#'):
            continue                                # stale active value from the package default
        kept.append(l)
    block = ['', BROWSED_MARKER + ' -------------------------------',
             '# dnssd only: no legacy UDP/631 listener (CVE-2024-47176 class).',
             '# Driverless: auto-create queues for IPP Everywhere / AirPrint printers.',
             '# Arch/cups-browsed default is LocalOnly, which ignores LAN printers.']
    block += [f'{k} {v}' for k, v in BROWSED_KEYS.items()]
    new = '\n'.join(kept).rstrip('\n') + '\n' + '\n'.join(block) + '\n'
    if new == (txt or ''):
        return 'already ok'
    if txt is not None:
        _backup(root, path)
    with open(path, 'w') as f:
        f.write(new)
    return 'patched'


def _patch_systemgroup(root):
    """Make sure CUPS lets the desktop's admin group manage printers.

    Arch's package default is `SystemGroup sys root wheel`. A machine whose
    /etc/cups/cups-files.conf has no such line (seen 2026-09-21 on the first
    real second machine: the status check reported FAIL after a clean install)
    would refuse `lpadmin` from a normal admin user. Only acts when the active
    SystemGroup line is missing or names neither wheel nor sys: it appends
    'wheel' to an existing line (keeping any site-specific groups) or adds the
    upstream default line. Idempotent; the original is backed up first."""
    path = os.path.join(root, 'etc/cups/cups-files.conf')
    txt = _read(path)
    if txt is None:
        return 'skipped (no cups-files.conf yet)'
    if systemgroup_ok(root):
        return 'already ok'
    out, done = [], False
    for l in txt.splitlines():
        if not done and re.match(r'^SystemGroup\s', l):
            out.append(l.rstrip() + ' wheel')
            done = True
            continue
        out.append(l)
    if not done:
        out += ['', "# SelahOS: let the desktop's admin group manage printers (upstream Arch default)",
                'SystemGroup sys root wheel']
    _backup(root, path)
    with open(path, 'w') as f:
        f.write('\n'.join(out).rstrip('\n') + '\n')
    return 'patched'


SKIP_REPOS = ('[selahos-offline]', '[chaotic-aur]')


def _clean_pacman_conf(src='/etc/pacman.conf'):
    """Write a temp copy of pacman.conf without the repos that break installed
    systems ([selahos-offline] only exists on the live USB; [chaotic-aur] has no
    signing key here and its mirrors have outages). Any one failing repo aborts
    the whole sync. /etc/pacman.conf itself is never modified. Returns the temp
    path, or None if pacman.conf is unreadable."""
    import tempfile
    txt = _read(src)
    if txt is None:
        return None
    out, skip = [], False
    for line in txt.splitlines():
        if line.startswith('['):
            skip = line.strip() in SKIP_REPOS
        if not skip:
            out.append(line)
    fd, path = tempfile.mkstemp(prefix='selah-print-pacman-', suffix='.conf')
    with os.fdopen(fd, 'w') as f:
        f.write('\n'.join(out) + '\n')
    return path


def _pacman_hint(text):
    if re.search(r'404|failed retrieving|target not found|could not resolve host', text, re.I):
        return (' Your package database looks out of date. Re-run with --upgrade '
                '(a full system update, the supported way to fix this on Arch).')
    return ''


def configure(root='/', now=False, install_missing=False, upgrade=False):
    if root == '/' and os.geteuid() != 0:
        return dict(ok=False, error='configure must run as root (use pkexec or sudo).')
    steps = []
    if (install_missing or upgrade) and root == '/':
        conf = _clean_pacman_conf()
        base = ['pacman'] + (['--config', conf] if conf else [])
        try:
            if upgrade:
                rc, out, err = run(base + ['-Syu', '--noconfirm'], timeout=3600)
                steps.append(dict(step='system-upgrade', ok=(rc == 0),
                                  detail='done' if rc == 0 else (err or out).strip()[-300:]))
            wanted = wanted_packages()
            if run(['python3', '-c', 'import PyQt6.QtWidgets'], timeout=20)[0] != 0:
                wanted = wanted + ['python-pyqt6']       # the Print Center GUI needs it
            missing = [p for p in wanted if not pkg_installed(p)]
            if missing:
                rc, out, err = run(base + ['-S', '--needed', '--noconfirm'] + missing, timeout=1800)
                text = (err or out).strip()[-300:]
                steps.append(dict(step='install-packages', ok=(rc == 0),
                                  detail=(', '.join(missing) if rc == 0 else text + _pacman_hint(err + out))))
            else:
                steps.append(dict(step='install-packages', ok=True, detail='all present'))
        finally:
            if conf:
                os.unlink(conf)
    steps.append(dict(step='nsswitch', ok=True, detail=_patch_nsswitch(root)))
    steps.append(dict(step='cups-browsed.conf', ok=True, detail=_patch_browsed(root)))
    sg = _patch_systemgroup(root)
    steps.append(dict(step='cups-files.conf', ok=True, detail=sg))
    if sg == 'patched' and now and root == '/':
        run(['systemctl', 'restart', 'cups.service'], timeout=30)    # cupsd reads this file at start
    for unit in SERVICES:
        if not unit_exists(unit, root):
            steps.append(dict(step=f'enable {unit}', ok=False, detail='unit file missing'))
            continue
        cmd = ['systemctl'] + ([f'--root={root}'] if root != '/' else []) + ['enable'] + (['--now'] if now and root == '/' else []) + [unit]
        rc, out, err = run(cmd, timeout=60)
        steps.append(dict(step=f'enable {unit}', ok=(rc == 0),
                          detail='enabled' if rc == 0 else (err or out).strip()[-200:]))
    if now and root == '/':
        run(['systemctl', 'restart', 'cups-browsed.service'], timeout=30)
    return dict(ok=all(s['ok'] for s in steps), steps=steps)


# ── CLI ──────────────────────────────────────────────────────────────────

def _print_table(rows, cols):
    if not rows:
        return
    widths = [max(len(str(r.get(c, ''))) for r in rows + [dict((c, c) for c in cols)]) for c in cols]
    for r in [dict((c, c.upper()) for c in cols)] + rows:
        print('  '.join(str(r.get(c, '')).ljust(w) for c, w in zip(cols, widths)))


def main(argv=None):
    ap = argparse.ArgumentParser(prog='selah-print', description='SelahOS printer setup')
    sub = ap.add_subparsers(dest='cmd', required=True)

    def cmd(name, *args, **kw):
        p = sub.add_parser(name, **kw)
        p.add_argument('--json', action='store_true')
        for a, k in args:
            p.add_argument(*a if isinstance(a, tuple) else (a,), **k)
        return p

    cmd('discover', (('--timeout',), dict(type=float, default=4.0)))
    cmd('probe', ('target', {}))
    cmd('list', (('--no-markers',), dict(action='store_true')))
    cmd('add', ('target', {}), (('--name',), {}), (('--driver',), dict(default='auto')),
        (('--default',), dict(action='store_true')))
    for n in ('remove', 'default', 'test-page', 'cancel-all'):
        cmd(n, ('name', {}))
    cmd('jobs', ('name', dict(nargs='?')))
    cmd('cancel', ('job', {}))
    cmd('options', ('name', {}), (('--set',), dict(action='append', default=[])))
    cmd('status', (('--root',), dict(default='/')))
    cmd('configure', (('--root',), dict(default='/')), (('--now',), dict(action='store_true')),
        (('--install-missing',), dict(action='store_true')), (('--upgrade',), dict(action='store_true')))
    a = ap.parse_args(argv)
    js = a.json

    if a.cmd == 'discover':
        res = discover(a.timeout)
        if js:
            return emit(dict(ok=True, printers=res), True)
        if not res:
            print('No network printers found. Is the printer on and on the same network?')
        _print_table(res, ['name', 'ip', 'driver', 'already_added'])
        return res

    if a.cmd == 'probe':
        host = _host_of(a.target) if '://' in a.target else a.target
        info = probe_ipp(host)
        res = dict(ok=bool(info), **(info or dict(error='No IPP printer answered at that address.')))
        if js:
            return emit(res, True)
        print(json.dumps(res, indent=2))
        return res

    if a.cmd == 'list':
        res = list_queues(with_markers=not a.no_markers)
        if js:
            return emit(res, True)
        if not res['ok']:
            die(res['error'])
        _print_table(res['printers'], ['name', 'state', 'default', 'jobs', 'uri'])
        return res

    if a.cmd == 'add':
        res = add_printer(a.target, a.name, a.driver, a.default)
    elif a.cmd == 'remove':
        res = simple(['lpadmin', '-x', a.name], 'Printer removed.')
    elif a.cmd == 'default':
        res = simple(['lpadmin', '-d', a.name], 'Default printer set.')
    elif a.cmd == 'test-page':
        res = test_page(a.name)
    elif a.cmd == 'cancel-all':
        res = simple(['cancel', '-a', a.name], 'All jobs cancelled.')
    elif a.cmd == 'cancel':
        res = simple(['cancel', a.job], 'Job cancelled.')
    elif a.cmd == 'jobs':
        res = list_jobs(a.name)
    elif a.cmd == 'options':
        res = None
        for kv in a.set:
            k, _, v = kv.partition('=')
            res = set_option(a.name, k, v)
            if not res['ok']:
                break
        if res is None:
            res = get_options(a.name)
    elif a.cmd == 'status':
        res = status(a.root)
    elif a.cmd == 'configure':
        res = configure(a.root, a.now, a.install_missing, a.upgrade)

    if js:
        emit(res, True)
    else:
        if a.cmd == 'status':
            for c in res['checks']:
                print(f"  {'OK  ' if c['ok'] else ('FAIL' if c['fatal'] else 'WARN')} {c['label']}"
                      + ('' if c['ok'] or not c['detail'] else f"  ({c['detail']})"))
        elif a.cmd == 'configure':
            for s in res.get('steps', []):
                print(f"  {'OK  ' if s['ok'] else 'FAIL'} {s['step']}: {s['detail']}")
            if not res['ok'] and 'error' in res:
                print(f"selah-print: {res['error']}", file=sys.stderr)
        elif res.get('ok'):
            print(res.get('message') or json.dumps({k: v for k, v in res.items() if k != 'ok'}, indent=2))
        else:
            print(f"selah-print: {res.get('error', 'failed')}", file=sys.stderr)
    return res


if __name__ == '__main__':
    result = main()
    if isinstance(result, dict) and result.get('ok') is False:
        sys.exit(2)
    sys.exit(0)
__SELAH_PAYLOAD_PAYLOAD_SELAH_PRINT__
}

payload_selahos_print_center() {
cat <<'__SELAH_PAYLOAD_PAYLOAD_SELAHOS_PRINT_CENTER__'
#!/usr/bin/env python3
# ============================================================
# SelahOS Print Center
# KDE Application Menu → Settings → SelahOS Print Center
#
# Finds printers on the network, sets them up (no vendor driver for any
# AirPrint / IPP Everywhere printer), and manages them: default printer,
# test page, toner levels, two-sided/color/paper defaults, print jobs.
# Once a printer is set up here it shows in the Print dialog of every app
# (they all talk to CUPS). All the real work is done by `selah-print`;
# this window only runs it in the background and shows the result.
#
# Runs as the normal user -- CUPS lets the wheel/sys groups manage
# printers over its local socket, so no password prompt for day-to-day use.
# Only "Repair printing" (system config) asks for admin rights.
#
# Copyright (C) 2026 Selah Technologies LLC
# ============================================================

import json
import os
import shutil
import subprocess
import sys

from PyQt6.QtCore import Qt, QThread, QTimer, pyqtSignal
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFrame, QHBoxLayout, QLabel, QLineEdit,
    QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QProgressBar,
    QPushButton, QScrollArea, QStackedWidget, QVBoxLayout, QWidget,
)

COLORS = {
    'bg': '#0B0F1A', 'bg2': '#111827', 'bg3': '#1A2030', 'gold': '#D6A85A',
    'parch': '#EDE4D4', 'muted': '#9A8D7B', 'teal': '#8EC3B8', 'red': '#B97A6F',
    'border': '#2A3042', 'green': '#6A9A7A',
}

STYLESHEET = f"""
QMainWindow, QWidget {{
    background-color: {COLORS['bg']}; color: {COLORS['parch']};
    font-family: 'Noto Sans', sans-serif; font-size: 14px;
}}
QLabel {{ background: transparent; }}
QPushButton {{
    background-color: {COLORS['gold']}; color: {COLORS['bg']}; border: none;
    border-radius: 4px; padding: 9px 20px; font-size: 13px; font-weight: bold;
}}
QPushButton:hover {{ background-color: #E6C27A; }}
QPushButton:disabled {{ background-color: {COLORS['border']}; color: {COLORS['muted']}; }}
QPushButton#quiet {{
    background: transparent; color: {COLORS['teal']}; border: 1px solid {COLORS['border']};
}}
QPushButton#quiet:hover {{ border-color: {COLORS['teal']}; }}
QPushButton#danger {{
    background: transparent; color: {COLORS['red']}; border: 1px solid {COLORS['red']};
}}
QPushButton#danger:hover {{ background: {COLORS['red']}; color: {COLORS['bg']}; }}
QPushButton#link {{
    background: transparent; color: {COLORS['muted']}; padding: 4px 8px; font-weight: normal;
}}
QPushButton#link:hover {{ color: {COLORS['gold']}; }}
QListWidget {{
    background: {COLORS['bg2']}; border: 1px solid {COLORS['border']};
    border-radius: 4px; outline: none;
}}
QListWidget::item {{ padding: 12px 10px; border-bottom: 1px solid {COLORS['border']}; }}
QListWidget::item:selected {{ background: {COLORS['bg3']}; color: {COLORS['gold']}; }}
QLineEdit, QComboBox {{
    background: {COLORS['bg2']}; border: 1px solid {COLORS['border']};
    border-radius: 4px; padding: 8px 10px; color: {COLORS['parch']};
}}
QComboBox QAbstractItemView {{ background: {COLORS['bg2']}; selection-background-color: {COLORS['bg3']}; }}
QProgressBar {{
    background: {COLORS['bg3']}; border: none; border-radius: 4px; height: 10px; text-align: center;
}}
QScrollArea {{ border: none; }}
"""

SELAH_PRINT = shutil.which('selah-print') or '/usr/local/bin/selah-print'

DUPLEX_LABELS = {'None': 'Off (one side)', 'DuplexNoTumble': 'Both sides — long edge',
                 'DuplexTumble': 'Both sides — short edge'}
COLOR_LABELS = {'RGB': 'Color', 'CMYK': 'Color', 'Gray': 'Grayscale', 'KGray': 'Grayscale'}
MARKER_NAMES = {'bk': 'Black', 'k': 'Black', 'c': 'Cyan', 'm': 'Magenta', 'y': 'Yellow'}
MARKER_FALLBACK = {'bk': '#C9C9C9', 'k': '#C9C9C9', 'c': '#00C8FF', 'm': '#FF3DBE', 'y': '#FFE600'}


class Worker(QThread):
    """Runs `selah-print <args> --json` (or any command) off the UI thread."""
    done = pyqtSignal(object, object)          # (result-dict, tag)

    def __init__(self, args, tag=None, prefix=None, parent=None):
        super().__init__(parent)
        self.args, self.tag, self.prefix = args, tag, prefix or []

    def run(self):
        cmd = self.prefix + [SELAH_PRINT] + self.args + ['--json']
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            try:
                res = json.loads(p.stdout)
            except ValueError:
                res = dict(ok=False, error=(p.stderr or p.stdout or 'No response').strip()[-300:])
        except (OSError, subprocess.TimeoutExpired) as e:
            res = dict(ok=False, error=str(e))
        self.done.emit(res, self.tag)


def label(text, color=None, size=None, bold=False, wrap=True):
    l = QLabel(text)
    l.setWordWrap(wrap)
    css = ''
    if color:
        css += f'color: {color};'
    if size:
        css += f'font-size: {size}px;'
    if bold:
        css += 'font-weight: bold;'
    if css:
        l.setStyleSheet(css)
    return l


def card():
    f = QFrame()
    f.setStyleSheet(f"QFrame#card {{ background: {COLORS['bg2']}; border: 1px solid {COLORS['border']}; border-radius: 6px; }}")
    f.setObjectName('card')
    return f


def clear_layout(layout):
    while layout.count():
        item = layout.takeAt(0)
        if item.widget():
            item.widget().deleteLater()
        elif item.layout():
            clear_layout(item.layout())


class SupplyBar(QWidget):
    def __init__(self, marker):
        super().__init__()
        lay = QHBoxLayout(self)
        lay.setContentsMargins(0, 2, 0, 2)
        key = marker['name'].lower()
        name = MARKER_NAMES.get(key, marker['name'])
        color = marker.get('color') or MARKER_FALLBACK.get(key, COLORS['teal'])
        if color.upper() == '#000000':
            color = '#C9C9C9'                 # pure black is invisible on the dark UI
        lvl = marker.get('level')
        n = label(name, wrap=False)
        n.setFixedWidth(80)
        bar = QProgressBar()
        bar.setRange(0, 100)
        bar.setTextVisible(False)
        bar.setValue(lvl if lvl is not None else 0)
        bar.setStyleSheet(f"QProgressBar::chunk {{ background: {color}; border-radius: 4px; }}")
        low = lvl is not None and lvl <= 10
        pct = label('unknown' if lvl is None else f'{lvl}%' + ('  low' if low else ''),
                    color=COLORS['red'] if low else COLORS['muted'], size=12, wrap=False)
        pct.setFixedWidth(80)
        lay.addWidget(n)
        lay.addWidget(bar, 1)
        lay.addWidget(pct)


class PrinterDetail(QWidget):
    """Right-hand panel for the selected printer."""
    changed = pyqtSignal()                    # ask main window to refresh

    def __init__(self, run_cmd):
        super().__init__()
        self.run_cmd = run_cmd                # run_cmd(args, tag, callback)
        self.printer = None
        self.lay = QVBoxLayout(self)
        self.lay.setContentsMargins(0, 0, 0, 0)

    def show_printer(self, p, options=None, jobs=None):
        clear_layout(self.lay)
        self.printer = p
        if not p:
            return
        title = label(p.get('description') or p['name'], COLORS['gold'], 22, True)
        self.lay.addWidget(title)
        sub = label(f"{p.get('model') or 'Printer'}  ·  {p.get('host') or p.get('uri') or ''}",
                    COLORS['muted'], 12)
        self.lay.addWidget(sub)

        text, color = self.status_of(p)
        chip = label(('● ' + text) + ('   ·   Default printer' if p['default'] else ''), color, 14, True)
        self.lay.addWidget(chip)
        self.lay.addSpacing(8)

        if p.get('markers'):
            box = card()
            bl = QVBoxLayout(box)
            bl.addWidget(label('Supplies', COLORS['teal'], 12, True))
            for m in p['markers']:
                bl.addWidget(SupplyBar(m))
            self.lay.addWidget(box)

        row = QHBoxLayout()
        b = QPushButton('Print test page')
        b.clicked.connect(self.test_page)
        row.addWidget(b)
        b2 = QPushButton('Make default')
        b2.setObjectName('quiet')
        b2.setEnabled(not p['default'])
        b2.clicked.connect(lambda: self.simple(['default', p['name']]))
        row.addWidget(b2)
        row.addStretch(1)
        b3 = QPushButton('Remove')
        b3.setObjectName('danger')
        b3.clicked.connect(self.remove)
        row.addWidget(b3)
        self.lay.addLayout(row)

        if options:
            box = card()
            bl = QVBoxLayout(box)
            bl.addWidget(label('Defaults for this printer', COLORS['teal'], 12, True))
            for o in options:
                if o['key'] not in ('Duplex', 'ColorModel', 'PageSize') or len(o['choices']) < 2:
                    continue
                r = QHBoxLayout()
                lbl = {'Duplex': 'Two-sided printing', 'ColorModel': 'Color', 'PageSize': 'Paper size'}[o['key']]
                r.addWidget(label(lbl, wrap=False), 1)
                cb = QComboBox()
                seen = set()
                for c in o['choices']:
                    text = (DUPLEX_LABELS if o['key'] == 'Duplex' else COLOR_LABELS if o['key'] == 'ColorModel' else {}).get(c, c)
                    if (o['key'] == 'ColorModel' and text in seen):
                        continue
                    seen.add(text)
                    cb.addItem(text, c)
                idx = cb.findData(o['default'])
                if idx >= 0:
                    cb.setCurrentIndex(idx)
                cb.activated.connect(lambda _i, cb=cb, key=o['key']: self.set_option(key, cb.currentData()))
                cb.setMinimumWidth(240)
                r.addWidget(cb)
                bl.addLayout(r)
            self.lay.addWidget(box)

        if jobs is not None:
            box = card()
            bl = QVBoxLayout(box)
            head = QHBoxLayout()
            head.addWidget(label(f'Print queue ({len(jobs)})', COLORS['teal'], 12, True), 1)
            if jobs:
                c = QPushButton('Cancel all')
                c.setObjectName('link')
                c.clicked.connect(lambda: self.simple(['cancel-all', p['name']]))
                head.addWidget(c)
            bl.addLayout(head)
            if not jobs:
                bl.addWidget(label('Nothing waiting to print.', COLORS['muted'], 13))
            for j in jobs[:6]:
                bl.addWidget(label(f"{j['id']}   {j['user']}   {j['size'] // 1024} KB", COLORS['parch'], 12))
            self.lay.addWidget(box)
        self.lay.addStretch(1)

    @staticmethod
    def status_of(p):
        low = [m['name'] for m in p.get('markers', []) if m.get('level') is not None and m['level'] <= 10]
        if p.get('reachable') is False:
            return "Can't reach the printer — is it turned on and on this network?", COLORS['red']
        if p['state'] == 'stopped':
            return 'Paused', COLORS['gold']
        if p['state'] == 'printing':
            return 'Printing…', COLORS['gold']
        if low:
            return 'Ready — toner low (' + ', '.join(low) + ')', COLORS['gold']
        return 'Ready', COLORS['green']

    def simple(self, args):
        self.run_cmd(args, 'action', lambda r: self.changed.emit())

    def set_option(self, key, val):
        self.run_cmd(['options', self.printer['name'], '--set', f'{key}={val}'], 'action',
                     lambda r: None if r.get('ok') else QMessageBox.warning(self, 'Print Center', r.get('error', 'Failed')))

    def test_page(self):
        p = self.printer
        ans = QMessageBox.question(
            self, 'Print test page',
            f"Send a test page to {p.get('description') or p['name']}?\n\n"
            "It is a full-color page, so it uses some toner or ink.")
        if ans == QMessageBox.StandardButton.Yes:
            self.run_cmd(['test-page', p['name']], 'action',
                         lambda r: (QMessageBox.information(self, 'Print Center', 'Test page sent.')
                                    if r.get('ok') else QMessageBox.warning(self, 'Print Center', r.get('error', 'Failed')),
                                    self.changed.emit()))

    def remove(self):
        p = self.printer
        if QMessageBox.question(self, 'Remove printer',
                                f"Remove {p.get('description') or p['name']} from this computer?\n"
                                "(The printer itself is not affected; you can add it again any time.)"
                                ) == QMessageBox.StandardButton.Yes:
            self.simple(['remove', p['name']])


class AddPage(QWidget):
    added = pyqtSignal()
    back = pyqtSignal()

    def __init__(self, run_cmd):
        super().__init__()
        self.run_cmd = run_cmd
        lay = QVBoxLayout(self)
        top = QHBoxLayout()
        bk = QPushButton('← Back')
        bk.setObjectName('quiet')
        bk.clicked.connect(self.back.emit)
        top.addWidget(bk)
        top.addStretch(1)
        lay.addLayout(top)
        lay.addWidget(label('Add a printer', COLORS['gold'], 22, True))
        lay.addWidget(label('SelahOS looks for printers on your network. Most printers made since about 2015 '
                            'work with no driver at all.', COLORS['muted'], 13))
        row = QHBoxLayout()
        self.scan_btn = QPushButton('Scan network again')
        self.scan_btn.clicked.connect(self.scan)
        row.addWidget(self.scan_btn)
        self.scan_status = label('', COLORS['muted'], 13)
        row.addWidget(self.scan_status, 1)
        lay.addLayout(row)
        self.results = QVBoxLayout()
        holder = QWidget()
        holder.setLayout(self.results)
        sc = QScrollArea()
        sc.setWidgetResizable(True)
        sc.setWidget(holder)
        lay.addWidget(sc, 1)
        lay.addWidget(label('Can\'t see it? Enter its address', COLORS['teal'], 12, True))
        man = QHBoxLayout()
        self.addr = QLineEdit()
        self.addr.setPlaceholderText('IP address or name, e.g. 192.168.1.50 or printer.local')
        self.addr.returnPressed.connect(self.add_manual)
        man.addWidget(self.addr, 1)
        b = QPushButton('Add')
        b.clicked.connect(self.add_manual)
        man.addWidget(b)
        lay.addLayout(man)

    def scan(self):
        self.scan_btn.setEnabled(False)
        self.scan_status.setText('Looking for printers…')
        clear_layout(self.results)
        self.run_cmd(['discover', '--timeout', '5'], 'scan', self.scan_done)

    def scan_done(self, r):
        self.scan_btn.setEnabled(True)
        clear_layout(self.results)
        found = r.get('printers', []) if r.get('ok') else []
        if not r.get('ok'):
            self.scan_status.setText(r.get('error', 'Scan failed.'))
            return
        self.scan_status.setText(f'Found {len(found)} printer(s).' if found else
                                 'No printers found. Check that the printer is on and connected to the same network.')
        for p in found:
            box = card()
            hl = QHBoxLayout(box)
            info = QVBoxLayout()
            info.addWidget(label(p['model'] or p['name'], COLORS['parch'], 15, True))
            kind = 'No driver needed (AirPrint / IPP Everywhere)' if p['driver'] == 'driverless' else 'Will look for a driver'
            feats = ', '.join(x for x in ('color' if p['color'] else 'black & white',
                                          'two-sided' if p['duplex'] else '') if x)
            info.addWidget(label(f"{p['ip']}  ·  {feats}  ·  {kind}", COLORS['muted'], 12))
            hl.addLayout(info, 1)
            if p['already_added']:
                hl.addWidget(label('✓ Added', COLORS['green'], 13, True, wrap=False))
            else:
                b = QPushButton('Add')
                b.clicked.connect(lambda _c, ip=p['ip'], b=b: self.add(ip, b))
                hl.addWidget(b)
            self.results.addWidget(box)
        self.results.addStretch(1)

    def add(self, target, btn=None):
        if btn:
            btn.setEnabled(False)
            btn.setText('Setting up…')
        self.run_cmd(['add', target], 'add', lambda r: self.add_done(r, btn))

    def add_manual(self):
        t = self.addr.text().strip()
        if t:
            self.add(t)

    def add_done(self, r, btn):
        if r.get('ok'):
            self.addr.clear()
            self.added.emit()
            return
        if btn:
            btn.setEnabled(True)
            btn.setText('Add')
        msg = r.get('hint') or r.get('error', 'Could not add the printer.')
        QMessageBox.warning(self, 'Print Center', msg)


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('SelahOS Print Center')
        self.resize(940, 640)
        self.workers = set()
        self.printers = []
        self.selected = None

        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(20, 16, 20, 10)

        head = QHBoxLayout()
        head.addWidget(label('Print Center', COLORS['gold'], 26, True, wrap=False))
        head.addStretch(1)
        adv = QPushButton('KDE printer settings')
        adv.setObjectName('link')
        adv.clicked.connect(self.open_kde)
        head.addWidget(adv)
        rep = QPushButton('Repair printing')
        rep.setObjectName('link')
        rep.clicked.connect(self.repair)
        head.addWidget(rep)
        outer.addLayout(head)

        self.stack = QStackedWidget()
        outer.addWidget(self.stack, 1)

        # page 0: printer list + detail
        main = QWidget()
        ml = QHBoxLayout(main)
        ml.setContentsMargins(0, 8, 0, 0)
        left = QVBoxLayout()
        self.listw = QListWidget()
        self.listw.setFixedWidth(270)
        self.listw.currentRowChanged.connect(self.on_select)
        left.addWidget(self.listw, 1)
        add = QPushButton('+  Add printer')
        add.clicked.connect(self.open_add)
        left.addWidget(add)
        ml.addLayout(left)
        self.detail = PrinterDetail(self.run_cmd)
        self.detail.changed.connect(self.refresh)
        self.empty = QWidget()
        el = QVBoxLayout(self.empty)
        el.addStretch(1)
        el.addWidget(label('No printers yet', COLORS['gold'], 22, True), 0, Qt.AlignmentFlag.AlignHCenter)
        self.empty_text = label('Click “Add printer” — SelahOS will look for printers on your network.',
                                COLORS['muted'], 14)
        self.empty_text.setAlignment(Qt.AlignmentFlag.AlignCenter)
        el.addWidget(self.empty_text)
        el.addStretch(1)
        self.right = QStackedWidget()
        self.right.addWidget(self.detail)
        self.right.addWidget(self.empty)
        ml.addWidget(self.right, 1)
        self.stack.addWidget(main)

        # page 1: add
        self.add_page = AddPage(self.run_cmd)
        self.add_page.back.connect(lambda: self.stack.setCurrentIndex(0))
        self.add_page.added.connect(self.after_add)
        self.stack.addWidget(self.add_page)

        self.status = label('', COLORS['muted'], 12)
        outer.addWidget(self.status)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(10000)
        self.first = True
        self.refresh()

    # -- plumbing ----------------------------------------------------
    def run_cmd(self, args, tag, callback, prefix=None):
        w = Worker(args, tag, prefix, self)
        self.workers.add(w)
        w.done.connect(lambda res, _t, w=w: (self.workers.discard(w), callback(res)))
        w.start()

    # -- list --------------------------------------------------------
    def refresh(self):
        if self.stack.currentIndex() != 0 or any(w.tag == 'list' and w.isRunning() for w in self.workers):
            return
        self.run_cmd(['list'], 'list', self.on_list)

    def on_list(self, r):
        if not r.get('ok'):
            self.printers = []
            self.status.setText('⚠ ' + r.get('error', 'Cannot reach the print service.'))
            self.status.setStyleSheet(f"color: {COLORS['red']}; font-size: 12px;")
            self.right.setCurrentWidget(self.empty)
            self.empty_text.setText('The print service is not running.\nUse “Repair printing” at the top right.')
            return
        self.status.setText('Print service running.  Printers you add here appear in every app’s Print dialog.')
        self.status.setStyleSheet(f"color: {COLORS['muted']}; font-size: 12px;")
        self.printers = r['printers']
        keep = self.selected
        self.listw.blockSignals(True)
        self.listw.clear()
        for p in self.printers:
            text, color = PrinterDetail.status_of(p)
            short = text.split(' — ')[0] + ('  ·  toner low' if 'toner low' in text else '')
            it = QListWidgetItem(f"{p.get('description') or p['name']}\n{short}"
                                 + ('  ·  default' if p['default'] else ''))
            it.setData(Qt.ItemDataRole.UserRole, p['name'])
            self.listw.addItem(it)
        self.listw.blockSignals(False)
        if not self.printers:
            self.right.setCurrentWidget(self.empty)
            self.empty_text.setText('Click “Add printer” — SelahOS will look for printers on your network.')
            if self.first:
                self.first = False
                self.open_add()
            return
        self.first = False
        idx = next((i for i, p in enumerate(self.printers) if p['name'] == keep), 0)
        self.listw.setCurrentRow(idx)
        self.on_select(idx)

    def on_select(self, row):
        if row < 0 or row >= len(self.printers):
            return
        p = self.printers[row]
        self.selected = p['name']
        self.right.setCurrentWidget(self.detail)
        self.detail.show_printer(p)              # show immediately, fill options/jobs when they arrive
        name = p['name']
        self.run_cmd(['options', name], 'opts', lambda o, name=name, p=p: self.fill(name, p, o, None))

    def fill(self, name, p, opts, jobs):
        if self.selected != name:
            return
        options = opts.get('options') if opts.get('ok') else None
        self.run_cmd(['jobs', name], 'jobs', lambda j, name=name: self._final(name, p, options, j))

    def _final(self, name, p, options, j):
        if self.selected == name:
            self.detail.show_printer(p, options, j.get('jobs', []) if j.get('ok') else None)

    # -- actions -----------------------------------------------------
    def open_add(self):
        self.stack.setCurrentIndex(1)
        self.add_page.scan()

    def after_add(self):
        self.stack.setCurrentIndex(0)
        self.selected = None
        self.refresh()

    def open_kde(self):
        for cmd in (['kcmshell6', 'kcm_printer_manager'], ['systemsettings', 'kcm_printer_manager']):
            if shutil.which(cmd[0]):
                subprocess.Popen(cmd)
                return
        QMessageBox.information(self, 'Print Center', 'KDE printer settings are not installed.')

    def repair(self):
        if QMessageBox.question(
                self, 'Repair printing',
                'This re-applies the SelahOS printing setup (network printer discovery, print service) '
                'and installs anything missing. It needs your administrator password.'
        ) != QMessageBox.StandardButton.Yes:
            return
        self.status.setText('Repairing… (waiting for the administrator password)')

        def done(r):
            bad = [s for s in r.get('steps', []) if not s['ok']]
            if r.get('ok'):
                QMessageBox.information(self, 'Print Center', 'Printing setup repaired.')
            else:
                QMessageBox.warning(self, 'Print Center', r.get('error') or
                                    'Some steps failed:\n' + '\n'.join(f"{s['step']}: {s['detail']}" for s in bad))
            self.refresh()

        self.run_cmd(['configure', '--now', '--install-missing'], 'repair', done, prefix=['pkexec'])


def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLESHEET)
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
__SELAH_PAYLOAD_PAYLOAD_SELAHOS_PRINT_CENTER__
}

payload_desktop_entry() {
cat <<'__SELAH_PAYLOAD_PAYLOAD_DESKTOP_ENTRY__'
[Desktop Entry]
Type=Application
Name=SelahOS Print Center
GenericName=Printers
Comment=Find, add and manage printers — no drivers needed for most network printers
Exec=selahos-print-center
Icon=printer
Terminal=false
StartupNotify=true
Categories=System;Settings;HardwareSettings;Qt;
Keywords=printer;print;printing;cups;scanner;toner;ink;airprint;brother;hp;epson;canon;
__SELAH_PAYLOAD_PAYLOAD_DESKTOP_ENTRY__
}

payload_print_txt() {
cat <<'__SELAH_PAYLOAD_PAYLOAD_PRINT_TXT__'
# Printing package set for selah-setup (installer): CUPS + network printer
# discovery + the KDE printer settings, so SelahOS can find a printer on the
# network and every app's Print dialog can use it. Single source of truth,
# shared with tools/build-offline-repo.sh (same contract as base.txt).
#
# 2026-09-21 (Print Center): modern network printers (AirPrint / IPP
# Everywhere) need no vendor driver -- CUPS builds the queue from the
# printer's own IPP attributes. Set up + configured by `selah-print`
# (see airootfs/usr/local/bin/selah-print).
cups
cups-filters
cups-browsed

# gs renders PDF/PS pages to the raster the printer wants (gstoraster).
# Was live-ISO-only before (packages.x86_64) -- same "live-only gap" class
# as the items in base.txt.
ghostscript

# mDNS/DNS-SD: how printers announce themselves. nss-mdns lets .local
# printer names resolve (selah-print configure patches nsswitch.conf).
avahi
nss-mdns

# KDE "Printers" settings page + tray applet with job notifications.
print-manager

# Drivers for older/non-driverless printers (Epson, Canon, many others).
gutenprint

# USB printers that speak IPP-over-USB then work driverless too.
ipp-usb

# NOT here: brlaser (open driver for older Brother mono lasers) lives only
# in chaotic-aur, which the installer's pacstrap config deliberately strips
# (see selah-setup _pacstrap_pacman_conf). Add it via packaging/ + local-repo
# if older Brother models turn up -- the HL-L3230CDW-class needs no driver.
__SELAH_PAYLOAD_PAYLOAD_PRINT_TXT__
}


main "$@"
