"""
Belvedere's backend — the ONLY module allowed to touch libvirt, subprocess,
or anything hardware/VM-related. UI code (main_window.py etc.) must go
through here, never call virsh/libvirt directly. This is what makes
Belvedere inherit the CLI backend's portability instead of re-solving it:
every guest-OS-specific / hardware-specific decision (CPU model, firmware
paths, disk layout, capability gating) already lives in the shell scripts
and macos-libvirt-domain.xml.template this module shells out to — nothing
about a different machine's hardware should ever need a code change here.
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

import libvirt

SCRIPT_DIR = Path(__file__).resolve().parent.parent  # .../tools/vm-assistant
LIBVIRT_URI = "qemu:///system"


@dataclass
class VMInfo:
    name: str
    state: str  # "running", "shut off", "paused", etc.
    os_kind: str  # "windows", "macos", "linux", "unknown" — guessed from name
    guest_id: int | None  # libvirt domain ID if running, else None


def _connect() -> libvirt.virConnect:
    conn = libvirt.open(LIBVIRT_URI)
    if conn is None:
        raise RuntimeError(f"Failed to open libvirt connection to {LIBVIRT_URI}")
    return conn


def _guess_os_kind(name: str) -> str:
    if "win" in name:
        return "windows"
    if "macos" in name:
        return "macos"
    if "linux" in name:
        return "linux"
    return "unknown"


_STATE_NAMES = {
    libvirt.VIR_DOMAIN_NOSTATE: "no state",
    libvirt.VIR_DOMAIN_RUNNING: "running",
    libvirt.VIR_DOMAIN_BLOCKED: "blocked",
    libvirt.VIR_DOMAIN_PAUSED: "paused",
    libvirt.VIR_DOMAIN_SHUTDOWN: "shutting down",
    libvirt.VIR_DOMAIN_SHUTOFF: "shut off",
    libvirt.VIR_DOMAIN_CRASHED: "crashed",
    libvirt.VIR_DOMAIN_PMSUSPENDED: "suspended",
}


def list_vms() -> list[VMInfo]:
    """All selah-* domains, matching `selah-vm-assistant.sh status`'s scope."""
    conn = _connect()
    try:
        vms = []
        for dom in conn.listAllDomains():
            name = dom.name()
            if not name.startswith("selah-"):
                continue
            state, _ = dom.state()
            vms.append(
                VMInfo(
                    name=name,
                    state=_STATE_NAMES.get(state, "unknown"),
                    os_kind=_guess_os_kind(name),
                    guest_id=dom.ID() if dom.isActive() else None,
                )
            )
        return sorted(vms, key=lambda v: v.name)
    finally:
        conn.close()


def start_vm(name: str) -> None:
    conn = _connect()
    try:
        dom = conn.lookupByName(name)
        if not dom.isActive():
            dom.create()
    finally:
        conn.close()


def stop_vm(name: str, force: bool = False) -> None:
    conn = _connect()
    try:
        dom = conn.lookupByName(name)
        if not dom.isActive():
            return
        if force:
            dom.destroy()
        else:
            dom.shutdown()
    finally:
        conn.close()


def get_display_uri(name: str) -> str | None:
    """Returns e.g. 'spice://127.0.0.1:5900' — works for any graphics
    protocol (unlike `virsh vncdisplay`, which only works for VNC)."""
    conn = _connect()
    try:
        dom = conn.lookupByName(name)
        if not dom.isActive():
            return None
        result = subprocess.run(
            ["virsh", "--connect", LIBVIRT_URI, "domdisplay", name],
            capture_output=True, text=True, timeout=10,
        )
        display = result.stdout.strip()
        return display or None
    finally:
        conn.close()


def get_guest_ip(name: str) -> str | None:
    """Returns the first IPv4 lease address, or None if unavailable yet."""
    result = subprocess.run(
        ["virsh", "--connect", LIBVIRT_URI, "domifaddr", name],
        capture_output=True, text=True, timeout=10,
    )
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "ipv4":
            return parts[3].split("/")[0]
    return None


def launch_viewer(vm: VMInfo) -> subprocess.Popen:
    """
    Launches the appropriate external viewer for this VM's OS — remote-viewer
    (SPICE) for macOS, xfreerdp (RDP) for Windows. No embedded rendering in
    v1 — see the plan's "explicitly out of scope" list.
    """
    if vm.os_kind == "windows":
        ip = get_guest_ip(vm.name)
        if not ip:
            raise RuntimeError(
                f"No IP yet for '{vm.name}' — guest may still be booting. "
                f"Retry, or check: virsh --connect {LIBVIRT_URI} domifaddr {vm.name}"
            )
        return subprocess.Popen(
            ["xfreerdp", f"/v:{ip}", "/cert:ignore"],
            start_new_session=True,
        )
    else:
        # macOS (and anything else) — SPICE via remote-viewer (08-29,
        # switched from VNC/gvncviewer for interactive responsiveness —
        # see macos-libvirt-domain.xml.template's comment on the graphics
        # element for the reasoning). krdc is never used here regardless:
        # confirmed broken (black canvas) on this host's Wayland session,
        # see project memory / RESUME notes for 2026-08-28.
        display = get_display_uri(vm.name)
        if not display:
            raise RuntimeError(f"'{vm.name}' has no display — is it running?")
        return subprocess.Popen(
            ["remote-viewer", display],
            start_new_session=True,
        )


def run_capability_check(memory_mb: int, required_cpu_flag: str = "") -> tuple[bool, str]:
    """Runs the same Phase-0 gate the CLI scripts use, for the New VM wizard
    to surface a clear in-UI error instead of a terminal exit code."""
    args = ["bash", str(SCRIPT_DIR / "capability-check.sh"), str(memory_mb)]
    if required_cpu_flag:
        args.append(required_cpu_flag)
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    return result.returncode == 0, (result.stdout + result.stderr)


def build_vm(kind: str, version_or_variant: str, on_output) -> subprocess.Popen:
    """
    Kicks off the same selah-vm-windows10.sh / selah-vm-macos.sh <version>
    scripts the CLI uses, streaming output line-by-line to on_output(str) —
    no reimplementation of install logic here, matching the plan's core
    design constraint.
    """
    if kind == "windows":
        args = ["bash", str(SCRIPT_DIR / "selah-vm-windows10.sh")]
    elif kind == "macos":
        args = ["bash", str(SCRIPT_DIR / "selah-vm-macos.sh"), version_or_variant]
    else:
        raise ValueError(f"Unknown kind: {kind!r}")

    proc = subprocess.Popen(
        args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    return proc
