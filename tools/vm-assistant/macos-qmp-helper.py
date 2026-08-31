#!/usr/bin/env python3
"""Minimal QEMU QMP client for driving a headless macOS VM's console.

Same idea as the `virsh send-key` / `virsh screenshot` pattern already used
for the Windows VMs in this project, just talking to raw QEMU's QMP socket
directly instead of going through libvirt (the macOS scripts don't use
libvirt). No external dependencies — just a unix socket and JSON lines.

Used as a library by macos-install-automate.py, and directly from the shell
for one-off calibration/debugging:

  ./macos-qmp-helper.py --socket ~/vm-build/macos-sonoma/qmp.sock screenshot out.png
  ./macos-qmp-helper.py --socket ~/vm-build/macos-sonoma/qmp.sock sendtext "Macintosh HD"
  ./macos-qmp-helper.py --socket ~/vm-build/macos-sonoma/qmp.sock sendkey ret
  ./macos-qmp-helper.py --socket ~/vm-build/macos-sonoma/qmp.sock click 0.5 0.5
"""
import argparse
import json
import socket
import sys
import time

# US QWERTY: char -> (qcode, needs_shift)
_BASE = {
    "a": "a", "b": "b", "c": "c", "d": "d", "e": "e", "f": "f", "g": "g",
    "h": "h", "i": "i", "j": "j", "k": "k", "l": "l", "m": "m", "n": "n",
    "o": "o", "p": "p", "q": "q", "r": "r", "s": "s", "t": "t", "u": "u",
    "v": "v", "w": "w", "x": "x", "y": "y", "z": "z",
    "0": "0", "1": "1", "2": "2", "3": "3", "4": "4",
    "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
    " ": "spc", "-": "minus", "=": "equal", "[": "bracket_left",
    "]": "bracket_right", ";": "semicolon", "'": "apostrophe",
    "`": "grave_accent", "\\": "backslash", ",": "comma", ".": "dot",
    "/": "slash",
}
_SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal",
    "{": "bracket_left", "}": "bracket_right", ":": "semicolon",
    '"': "apostrophe", "~": "grave_accent", "|": "backslash",
    "<": "comma", ">": "dot", "?": "slash",
}
_NAMED_KEYS = {
    "enter": "ret", "return": "ret", "esc": "esc", "escape": "esc",
    "tab": "tab", "space": "spc", "backspace": "backspace",
    "delete": "delete", "up": "up", "down": "down", "left": "left",
    "right": "right",
}


def char_to_qcode(ch):
    """Return (qcode, needs_shift) for a single character."""
    if ch.isalpha() and ch.isupper():
        return ch.lower(), True
    if ch in _BASE:
        return _BASE[ch], False
    if ch in _SHIFTED:
        return _SHIFTED[ch], True
    raise ValueError(f"no qcode mapping for character {ch!r}")


class QMPClient:
    def __init__(self, sock_path, timeout=10):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(sock_path)
        self._reader = self.sock.makefile("rb")
        self._greeting = self._read_msg()  # QMP banner
        self._send({"execute": "qmp_capabilities"})
        self._read_msg()  # capabilities ack

    def _read_msg(self):
        line = self._reader.readline()
        if not line:
            raise ConnectionError("QMP socket closed unexpectedly")
        return json.loads(line)

    def _send(self, obj):
        self.sock.sendall((json.dumps(obj) + "\n").encode())

    def execute(self, command, arguments=None):
        payload = {"execute": command}
        if arguments is not None:
            payload["arguments"] = arguments
        self._send(payload)
        while True:
            msg = self._read_msg()
            if "return" in msg or "error" in msg:
                if "error" in msg:
                    raise RuntimeError(f"QMP command {command!r} failed: {msg['error']}")
                return msg["return"]
            # else: an async event notification, keep waiting for our reply

    def _key_event(self, qcode, down):
        return {
            "type": "key",
            "data": {"down": down, "key": {"type": "qcode", "data": qcode}},
        }

    def press_key(self, qcode, hold_ms=30):
        self.execute("input-send-event", {"events": [self._key_event(qcode, True)]})
        time.sleep(hold_ms / 1000.0)
        self.execute("input-send-event", {"events": [self._key_event(qcode, False)]})

    def send_key_combo(self, qcodes, hold_ms=30):
        """Press all qcodes down together (in order), then release in reverse order."""
        self.execute("input-send-event", {"events": [self._key_event(q, True) for q in qcodes]})
        time.sleep(hold_ms / 1000.0)
        self.execute("input-send-event", {"events": [self._key_event(q, False) for q in reversed(qcodes)]})

    def send_key(self, name, hold_ms=30):
        qcode = _NAMED_KEYS.get(name.lower(), name.lower())
        self.press_key(qcode, hold_ms=hold_ms)

    def send_text(self, text, inter_char_ms=40):
        for ch in text:
            qcode, needs_shift = char_to_qcode(ch)
            if needs_shift:
                self.send_key_combo(["shift", qcode])
            else:
                self.press_key(qcode)
            time.sleep(inter_char_ms / 1000.0)

    def move(self, x_frac, y_frac):
        """Absolute pointer move, x_frac/y_frac in [0.0, 1.0]."""
        axis_max = 32767
        x = int(max(0.0, min(1.0, x_frac)) * axis_max)
        y = int(max(0.0, min(1.0, y_frac)) * axis_max)
        events = [
            {"type": "abs", "data": {"axis": "x", "value": x}},
            {"type": "abs", "data": {"axis": "y", "value": y}},
        ]
        self.execute("input-send-event", {"events": events})

    def click(self, x_frac, y_frac, button="left", hold_ms=50):
        self.move(x_frac, y_frac)
        down = {"type": "btn", "data": {"down": True, "button": button}}
        up = {"type": "btn", "data": {"down": False, "button": button}}
        self.execute("input-send-event", {"events": [down]})
        time.sleep(hold_ms / 1000.0)
        self.execute("input-send-event", {"events": [up]})

    def screenshot(self, out_path):
        # 'format: png' requires QEMU >= 7.1 (this project already requires
        # QEMU >= 8.2.2 per OSX-KVM's own README) — avoids the raw-PPM output
        # older QEMU defaults to, so downstream tools can read it directly.
        self.execute("screendump", {"filename": out_path, "format": "png"})

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--socket", required=True, help="Path to the QMP unix socket")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("screenshot")
    sp.add_argument("out_path")

    sp = sub.add_parser("sendkey")
    sp.add_argument("key", help="named key (ret/tab/esc/...) or a single qcode")

    sp = sub.add_parser("sendtext")
    sp.add_argument("text")

    sp = sub.add_parser("click")
    sp.add_argument("x_frac", type=float)
    sp.add_argument("y_frac", type=float)

    sp = sub.add_parser("move")
    sp.add_argument("x_frac", type=float)
    sp.add_argument("y_frac", type=float)

    args = p.parse_args()
    qmp = QMPClient(args.socket)
    try:
        if args.cmd == "screenshot":
            qmp.screenshot(args.out_path)
            print(f"saved {args.out_path}")
        elif args.cmd == "sendkey":
            qmp.send_key(args.key)
        elif args.cmd == "sendtext":
            qmp.send_text(args.text)
        elif args.cmd == "click":
            qmp.click(args.x_frac, args.y_frac)
        elif args.cmd == "move":
            qmp.move(args.x_frac, args.y_frac)
    finally:
        qmp.close()


if __name__ == "__main__":
    main()
