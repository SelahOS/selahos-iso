#!/usr/bin/env python3
"""Build selahos-print-center-install-<version>.sh from the shipped sources.

The installer embeds selah-print, selahos-print-center, the .desktop entry and
print.txt verbatim (quoted heredocs), so the download can never drift from what
the ISO ships. Usage: build-installer.py [VERSION]   (default: today, YYYY-MM-DD; add -r2, -r3... for a re-issue that must not share a filename with an earlier one)
"""
import datetime
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE = os.path.normpath(os.path.join(HERE, '..', '..', 'selahos-iso-v3', 'airootfs'))

PAYLOADS = [
    ('payload_selah_print',          'usr/local/bin/selah-print'),
    ('payload_selahos_print_center', 'usr/local/bin/selahos-print-center'),
    ('payload_desktop_entry',        'usr/share/applications/selahos-print-center.desktop'),
    ('payload_print_txt',            'usr/local/share/selahos-install-packages/print.txt'),
]

version = sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat()
if not re.fullmatch(r'\d{4}-\d{2}-\d{2}(-r\d+)?', version):
    sys.exit('VERSION must look like 2026-09-21, or 2026-09-21-r2 for a corrected re-issue')

blocks = []
for func, rel in PAYLOADS:
    with open(os.path.join(PROFILE, rel)) as f:
        body = f.read()
    if not body.endswith('\n'):
        body += '\n'
    delim = '__SELAH_PAYLOAD_' + func.upper() + '__'
    if delim in body:
        sys.exit(f'{rel} contains the heredoc delimiter {delim}')
    blocks.append(f"{func}() {{\ncat <<'{delim}'\n{body}{delim}\n}}\n")

pk = []
with open(os.path.join(PROFILE, 'usr/local/share/selahos-install-packages/print.txt')) as f:
    for line in f:
        name = line.split('#', 1)[0].strip()
        if name:
            pk.append(name)

with open(os.path.join(HERE, 'installer.sh.in')) as f:
    out = f.read()
out = out.replace('@@VERSION@@', version).replace('@@PACKAGES_TEXT@@', ', '.join(pk))
out = out.replace('@@PAYLOAD@@', '\n'.join(blocks))
assert '@@' not in out, 'unreplaced placeholder'

dest = os.path.join(HERE, f'selahos-print-center-install-{version}.sh')
with open(dest, 'w') as f:
    f.write(out)
os.chmod(dest, 0o755)
print(dest)
