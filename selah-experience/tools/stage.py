#!/usr/bin/env python3
"""Stage data into an EMPTY directory; never activate themes or run privileged tools."""
import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]

def stage(destination):
    destination = Path(destination).resolve()
    if destination == Path("/") or (destination.exists() and any(destination.iterdir())):
        raise ValueError("Staging destination must be an empty directory, never a live root")
    destination.mkdir(parents=True, exist_ok=True)
    def copy_file(source, target):
        p = destination / target
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source, p)
        p.chmod(0o644)
    def copy_tree(source, target):
        for p in sorted((ROOT / source).rglob("*")):
            if p.is_symlink():
                raise ValueError(f"Symlinks are not allowed in payload: {p}")
            if p.is_file():
                copy_file(p.relative_to(ROOT), Path(target) / p.relative_to(ROOT / source))

    for name in ("selah-experience", "selah-experience-static"):
        for ext in ("script", "plymouth"):
            copy_file(f"boot/generated/{name}.{ext}", f"usr/share/plymouth/themes/{name}/{name}.{ext}")
    copy_tree("boot/selah-plymouth/assets", "usr/share/plymouth/themes/selah-experience/assets")
    copy_tree("login/selah-sddm", "usr/share/sddm/themes/selah-experience")
    copy_tree("plasma/org.selah.desktop", "usr/share/plasma/look-and-feel/org.selah.desktop")
    copy_file("plasma/SelahExperience.colors", "usr/share/color-schemes/SelahExperience.colors")
    for name in ("stillness", "horizon", "resonance"):
        copy_tree(f"scenes/{name}", f"usr/share/selah-experience/scenes/{name}")
    for name in ("README.md", "branding/PROVENANCE.md", "design/tokens.json"):
        copy_file(name, f"usr/share/doc/selah-experience/{name}")
    copy_tree("design", "usr/share/doc/selah-experience/design")
    copy_tree("docs", "usr/share/doc/selah-experience/docs")
    copy_file("LICENSE-NOTE.md", "usr/share/licenses/selah-experience/LICENSE-NOTE.md")
    for p in destination.rglob("*"):
        if p.is_dir(): p.chmod(0o755)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination")
    stage(parser.parse_args().destination)
