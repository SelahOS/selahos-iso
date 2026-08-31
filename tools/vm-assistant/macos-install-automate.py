#!/usr/bin/env python3
"""Experimental Disk Utility erase + Installer click-through automation for
the headless macOS VMs built by selah-vm-macos.sh.

This is the "unsolved wishlist item" piece — OSX-KVM's own README lists full
install automation as an open contribution request, there's no Windows-style
answer file for the macOS installer GUI. So this script does NOT hardcode
guessed pixel coordinates (that could click the wrong button, or worse, erase
the wrong disk) — it refuses to run any step whose click coordinate hasn't
been explicitly calibrated against a real, live screenshot first.

Workflow:
  1. Boot the VM with selah-vm-macos.sh (separately).
  2. Run this script with --calibrate to capture a screenshot and print the
     path. Read that screenshot (visually, e.g. via Claude's Read tool) and
     fill in the matching x/y fractions (0.0-1.0 of screen width/height) in
     the generated macos-ui-coords.<version>.json file.
  3. Run this script normally to execute the calibrated step sequence. Each
     step is screenshotted before and after, and marked done with a stage
     file (WORK_DIR/.stage-<name>-done) so a killed/interrupted run resumes
     at the right step instead of redoing the whole sequence.
  4. If a step's click lands wrong or the automation stalls, connect to the
     same VNC session (vncviewer localhost:<port>, printed by
     selah-vm-macos.sh) and finish that one step by hand — same fallback
     discipline used for the Windows virtio-win-guest-tools.exe install.

No coordinate is ever guessed. If a step needs one that isn't calibrated yet,
this script prints exactly which key is missing and exits without touching
the VM.
"""
import argparse
import importlib.util
import json
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# macos-qmp-helper.py has a hyphen in its name (matches this project's
# filename convention), so it can't be `import`ed normally — load it by path.
_spec = importlib.util.spec_from_file_location("macos_qmp_helper", SCRIPT_DIR / "macos-qmp-helper.py")
_qmp_helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_qmp_helper)
QMPClient = _qmp_helper.QMPClient

DEFAULT_STEPS = [
    {"name": "open_disk_utility", "action": "click", "coord": "disk_utility_icon", "wait_after_ms": 2000},
    {"name": "select_target_disk", "action": "click", "coord": "target_disk_row", "wait_after_ms": 500},
    {"name": "click_erase", "action": "click", "coord": "erase_button", "wait_after_ms": 1000},
    {"name": "focus_volume_name_field", "action": "click", "coord": "erase_name_field", "wait_after_ms": 300},
    {"name": "type_volume_name", "action": "sendtext", "text": "Macintosh HD", "wait_after_ms": 300},
    {"name": "confirm_erase", "action": "click", "coord": "erase_confirm_button", "wait_after_ms": 5000},
    {"name": "close_disk_utility", "action": "click", "coord": "disk_utility_close", "wait_after_ms": 1000},
    {"name": "open_installer", "action": "click", "coord": "install_macos_icon", "wait_after_ms": 3000},
    {"name": "installer_continue", "action": "click", "coord": "installer_continue_button", "wait_after_ms": 1500},
    {"name": "installer_agree", "action": "click", "coord": "installer_agree_button", "wait_after_ms": 1500},
    {"name": "installer_select_disk", "action": "click", "coord": "installer_target_disk", "wait_after_ms": 1000},
    {"name": "installer_install", "action": "click", "coord": "installer_install_button", "wait_after_ms": 2000},
]


def config_path(version):
    return SCRIPT_DIR / f"macos-ui-coords.{version}.json"


def load_or_init_config(version):
    path = config_path(version)
    if path.exists():
        return json.loads(path.read_text()), path
    cfg = {
        "version": version,
        "steps": DEFAULT_STEPS,
        # every coord key used by DEFAULT_STEPS, left null until calibrated
        "coords": {
            "disk_utility_icon": None,
            "target_disk_row": None,
            "erase_button": None,
            "erase_name_field": None,
            "erase_confirm_button": None,
            "disk_utility_close": None,
            "install_macos_icon": None,
            "installer_continue_button": None,
            "installer_agree_button": None,
            "installer_target_disk": None,
            "installer_install_button": None,
        },
    }
    path.write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"Wrote template config: {path}")
    return cfg, path


def work_dir(version):
    return Path.home() / "vm-build" / f"macos-{version}"


def marker_path(version, step_name):
    return work_dir(version) / f".stage-{step_name}-done"


def screenshot(qmp, version, label):
    shots = work_dir(version) / "screenshots"
    shots.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = shots / f"{ts}-{label}.png"
    qmp.screenshot(str(out))
    return out


def cmd_calibrate(args, qmp):
    path = screenshot(qmp, args.version, "calibrate")
    cfg, cfg_path = load_or_init_config(args.version)
    missing = [k for k, v in cfg["coords"].items() if v is None]
    print(f"Screenshot saved: {path}")
    print(f"Config: {cfg_path}")
    if missing:
        print("Still needs coordinates for:")
        for k in missing:
            print(f"  - {k}")
        print("Fill in [x_frac, y_frac] (0.0-1.0 of screen width/height) for each, "
              "reading them off the screenshot above, then re-run without --calibrate.")
    else:
        print("All coordinates are calibrated.")


def run_step(qmp, version, cfg, step, force):
    name = step["name"]
    marker = marker_path(version, name)
    if marker.exists() and not force:
        print(f"[skip] {name} (already done — use --force to redo)")
        return

    if step["action"] == "click":
        coord_key = step["coord"]
        coord = cfg["coords"].get(coord_key)
        if coord is None:
            print(f"ERROR: step '{name}' needs coordinate '{coord_key}', which isn't calibrated yet.", file=sys.stderr)
            print(f"Run with --calibrate first, fill it into {config_path(version)}, then retry.", file=sys.stderr)
            sys.exit(1)

    before = screenshot(qmp, version, f"before-{name}")
    print(f"[run] {name} (before: {before.name})")

    if step["action"] == "click":
        x, y = cfg["coords"][step["coord"]]
        qmp.click(x, y)
    elif step["action"] == "sendtext":
        qmp.send_text(step["text"])
    elif step["action"] == "sendkey":
        qmp.send_key(step["key"])
    else:
        raise ValueError(f"unknown action {step['action']!r} in step {name!r}")

    time.sleep(step.get("wait_after_ms", 500) / 1000.0)
    after = screenshot(qmp, version, f"after-{name}")
    marker.write_text(datetime.now().isoformat() + "\n")
    print(f"[done] {name} (after: {after.name})")


def cmd_run(args, qmp):
    cfg, _ = load_or_init_config(args.version)
    steps = cfg["steps"]
    if args.only:
        steps = [s for s in steps if s["name"] == args.only]
        if not steps:
            print(f"ERROR: no step named '{args.only}'", file=sys.stderr)
            sys.exit(1)
    for step in steps:
        run_step(qmp, args.version, cfg, step, force=args.force)


def cmd_reboot_watch(args, qmp):
    """Poll through the multi-reboot install cycle. No automatic 'done'
    detection (that needs actual vision on the screenshots, done by whoever
    is supervising the run) — this just keeps evidence flowing and halts
    immediately if the QEMU process itself dies, which IS unambiguous."""
    import subprocess
    pid_file = work_dir(args.version) / "qemu.pid"
    pid = int(pid_file.read_text().strip())
    deadline = time.time() + args.minutes * 60
    interval = max(15, args.interval)
    print(f"Watching PID {pid} for up to {args.minutes} minutes, screenshot every {interval}s...")
    while time.time() < deadline:
        try:
            import os
            os.kill(pid, 0)
        except ProcessLookupError:
            print("ERROR: QEMU process died during the install cycle.", file=sys.stderr)
            sys.exit(1)
        path = screenshot(qmp, args.version, "reboot-watch")
        print(f"  {datetime.now().strftime('%H:%M:%S')} alive, screenshot: {path.name}")
        time.sleep(interval)
    print("Watch window elapsed. Review the screenshots to judge install progress.")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("version", help="macOS version key, e.g. sonoma (matches selah-vm-macos.sh's WORK_DIR naming)")
    p.add_argument("--calibrate", action="store_true", help="take a screenshot and report missing coordinates, then exit")
    p.add_argument("--force", action="store_true", help="redo steps even if already marked done")
    p.add_argument("--only", help="run just this one step by name")
    p.add_argument("--reboot-watch", action="store_true", help="poll screenshots through the multi-reboot install cycle instead of running steps")
    p.add_argument("--minutes", type=int, default=90, help="reboot-watch duration (default 90)")
    p.add_argument("--interval", type=int, default=30, help="reboot-watch screenshot interval seconds (default 30, min 15)")
    args = p.parse_args()

    sock = work_dir(args.version) / "qmp.sock"
    if not sock.exists():
        print(f"ERROR: no QMP socket at {sock} — is the VM running (selah-vm-macos.sh {args.version})?", file=sys.stderr)
        sys.exit(1)

    qmp = QMPClient(str(sock))
    try:
        if args.calibrate:
            cmd_calibrate(args, qmp)
        elif args.reboot_watch:
            cmd_reboot_watch(args, qmp)
        else:
            cmd_run(args, qmp)
    finally:
        qmp.close()


if __name__ == "__main__":
    main()
