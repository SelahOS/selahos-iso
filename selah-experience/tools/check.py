#!/usr/bin/env python3
"""Dependency-free checks of budgets, metadata, references and safe package staging."""
import configparser
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import xml.etree.ElementTree as ET

from stage import stage

ROOT = Path(__file__).resolve().parents[1]
tokens = json.loads((ROOT / "design/tokens.json").read_text())
total = 0
for p in (ROOT / "boot/selah-plymouth/assets").glob("*.png"):
    data = p.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", p
    w, h = struct.unpack(">II", data[16:24])
    total += w*h*4
assert total <= tokens["performance"]["plymouthDecodedAssetsMaxBytes"], total
for p in ROOT.rglob("*.svg"):
    ET.parse(p)
assert (ROOT / "branding/selah-mark.svg").read_bytes() == (ROOT / "login/selah-sddm/selah-mark.svg").read_bytes()
original = ROOT.parent / "selahos-iso-v3/airootfs/usr/share/plymouth/themes/selahos/logo.svg"
if original.exists():
    assert original.read_bytes() == (ROOT / "branding/selah-mark.svg").read_bytes()
metadata = json.loads((ROOT / "plasma/org.selah.desktop/metadata.json").read_text())
assert metadata["KPackageStructure"] == "Plasma/LookAndFeel"
assert metadata["KPlugin"]["Id"] == "org.selah.desktop"
sddm = configparser.ConfigParser()
sddm.read(ROOT / "login/selah-sddm/metadata.desktop")
assert sddm["SddmGreeterTheme"]["QtVersion"] == "6"

with tempfile.TemporaryDirectory() as temp:
    dest = Path(temp) / "stage"
    stage(dest)
    paths = [p.relative_to(dest) for p in dest.rglob("*") if p.is_file()]
    assert all(str(p).startswith("usr/share/") for p in paths)
    assert not any("experiments" in p.parts for p in paths)
    payload = sum((dest / p).stat().st_size for p in paths)
    assert payload <= tokens["performance"]["packagePayloadMaxBytes"], payload
    for name in ("selah-experience", "selah-experience-static"):
        theme = configparser.ConfigParser()
        theme.read(dest / f"usr/share/plymouth/themes/{name}/{name}.plymouth")
        script = dest / theme["script"]["ScriptFile"].lstrip("/")
        image_dir = dest / theme["script"]["ImageDir"].lstrip("/")
        assert script.is_file() and image_dir.is_dir()
        for asset in ("logo.png", "point.png", "ring-0.png", "ring-1.png", "ring-2.png"):
            assert (image_dir / asset).is_file()
        text = script.read_text()
        for callback in ("SetDisplayPasswordFunction", "SetDisplayQuestionFunction",
                         "SetDisplayNormalFunction", "SetDisplayMessageFunction", "SetQuitFunction"):
            assert callback in text
    try:
        stage(dest)
        raise AssertionError("Nonempty destination must be rejected")
    except ValueError:
        pass
print(f"PASS: assets/metadata/staging; decoded PNGs {total} bytes; payload {payload} bytes.")
