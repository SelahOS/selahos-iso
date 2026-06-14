"""
MPK mini IV MIDI/SysEx core.
Protocol confirmed from live hardware (USB PID 005d):

  SysEx format: F0 47 00 5D <cmd> <len_msb> <len_lsb> [payload] F7
  Request preset:  cmd=0x66, data=[preset_idx]
  Response/set:    cmd=0x67, 276-byte payload:
    [0]      preset index (0-3)
    [1:17]   preset name (16-byte null-padded ASCII)
    [17]     0x00 (constant)
    [18]     0x09 (constant)
    [19]     0x00 (constant)
    [20]     arp tempo (BPM, 20-240 fits in 7 bits; device clips)
    [21]     arp division (0-7 = 1/4, 1/4T, 1/8, 1/8T, 1/16, 1/16T, 1/32, 1/32T)
    [22]     arp mode (0=Up,1=Down,2=Inclusive,3=Exclusive,4=Order,5=Random)
    [23]     arp enabled (0/1)
    [24]     arp octave range (0-3 = 1,2,3,4 octaves)
    [25]     clock source (0=Internal, 1=External)
    [26]     0x00 (constant)
    [27]     0x7F (constant)
    [28]     0x00 (constant)
    [29]     MIDI channel (1-16)
    [30:70]  Bank A pads (8 pads × 5 bytes): [note, 0x20+idx, idx, type_b3, type_b4]
    [70:110] Bank B pads (8 pads × 5 bytes): [note, 0x28+idx, 8+idx, type_b3, type_b4]
    [110:270] Knobs (8 × 20 bytes): [CC, min, max, mode, name[16]]
    [270:276] Footer (6 bytes, preset-type dependent — preserved as-is)
"""

import time
import threading
from dataclasses import dataclass, field
from typing import Optional, Callable

import rtmidi

AKAI_MFR_ID    = 0x47
MPK_DEVICE_ID  = 0x5D          # confirmed from live hardware
CMD_GET_PRESET = 0x66
CMD_SET_PRESET = 0x67

PAYLOAD_LEN    = 276
NUM_PADS_BANK  = 8              # pads per bank (A and B)
NUM_PADS       = NUM_PADS_BANK  # exposed in UI — bank selected separately
NUM_KNOBS      = 8

ARP_MODES      = ["Up", "Down", "Inclusive", "Exclusive", "Order", "Random"]
ARP_DIVISIONS  = ["1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T"]
ARP_OCT_RANGES = ["1 oct", "2 oct", "3 oct", "4 oct"]
KNOB_MODES     = ["Relative", "Absolute"]

NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
def note_name(n: int) -> str:
    return f"{NOTE_NAMES[n % 12]}{n // 12 - 1}"


@dataclass
class PadConfig:
    note: int = 36
    # type_b3 / type_b4: opaque pad-type bytes (velocity curve / mode).
    # Default 0x05/0x21 matches DAW preset. Preserved on round-trips.
    type_b3: int = 0x05
    type_b4: int = 0x21


@dataclass
class KnobConfig:
    cc:      int = 24
    min_val: int = 0
    max_val: int = 127
    mode:    int = 1   # 1=Absolute
    name:    str = ""


@dataclass
class Preset:
    index:        int = 0
    name:         str = "USER"
    midi_channel: int = 1
    arp_enabled:  bool = False
    arp_mode:     int  = 0
    arp_division: int  = 2     # 1/8
    arp_octave:   int  = 0
    arp_tempo:    int  = 120
    clock_source: int  = 0
    pads_a: list  = field(default_factory=lambda: [PadConfig(note=36+i) for i in range(8)])
    pads_b: list  = field(default_factory=lambda: [PadConfig(note=44+i) for i in range(8)])
    knobs:  list  = field(default_factory=lambda: [KnobConfig(cc=24+i, name=f"KNOB{i+1}") for i in range(8)])
    # Preserve unknown / constant bytes so round-trips don't corrupt device state
    _raw:         Optional[bytes] = field(default=None, repr=False)

    def to_sysex_payload(self) -> list:
        """Encode to 276-byte SysEx payload."""
        if self._raw and len(self._raw) == PAYLOAD_LEN:
            # Start from the last known-good raw bytes, only patch what we expose
            d = bytearray(self._raw)
        else:
            d = bytearray(PAYLOAD_LEN)
            # Constants
            d[17] = 0x00; d[18] = 0x09; d[19] = 0x00
            d[26] = 0x00; d[27] = 0x7F; d[28] = 0x00
            # Pad structural bytes (index fields)
            for i in range(8):
                d[30 + i*5 + 1] = 0x20 + i
                d[30 + i*5 + 2] = i
                d[70 + i*5 + 1] = 0x28 + i
                d[70 + i*5 + 2] = 8 + i

        d[0] = self.index
        # Name
        name_bytes = self.name.encode('ascii', errors='replace')[:16].ljust(16, b'\x00')
        d[1:17] = name_bytes
        # Arp / global
        d[20] = max(20, min(127, self.arp_tempo))
        d[21] = self.arp_division & 0x07
        d[22] = self.arp_mode & 0x07
        d[23] = int(self.arp_enabled)
        d[24] = self.arp_octave & 0x03
        d[25] = self.clock_source & 0x01
        d[29] = max(1, min(16, self.midi_channel))
        # Pads
        for i, pad in enumerate(self.pads_a[:8]):
            off = 30 + i * 5
            d[off] = pad.note & 0x7F
            d[off + 3] = pad.type_b3
            d[off + 4] = pad.type_b4
        for i, pad in enumerate(self.pads_b[:8]):
            off = 70 + i * 5
            d[off] = pad.note & 0x7F
            d[off + 3] = pad.type_b3
            d[off + 4] = pad.type_b4
        # Knobs
        for i, k in enumerate(self.knobs[:8]):
            off = 110 + i * 20
            d[off]     = k.cc & 0x7F
            d[off + 1] = k.min_val & 0x7F
            d[off + 2] = k.max_val & 0x7F
            d[off + 3] = k.mode & 0x01
            name_b = k.name.encode('ascii', errors='replace')[:16].ljust(16, b'\x00')
            d[off + 4:off + 20] = name_b
        return list(d)

    @classmethod
    def from_sysex_payload(cls, payload: list) -> "Preset":
        """Decode from 276-byte SysEx payload."""
        if len(payload) < PAYLOAD_LEN:
            return cls()
        d = payload
        p = cls(index=d[0])
        p._raw = bytes(d[:PAYLOAD_LEN])
        p.name         = bytes(d[1:17]).rstrip(b'\x00').decode('ascii', errors='?')
        p.arp_tempo    = d[20]
        p.arp_division = d[21] & 0x07
        p.arp_mode     = d[22] & 0x07
        p.arp_enabled  = bool(d[23])
        p.arp_octave   = d[24] & 0x03
        p.clock_source = d[25] & 0x01
        p.midi_channel = max(1, min(16, d[29]))
        p.pads_a = [PadConfig(note=d[30 + i*5],
                              type_b3=d[30 + i*5 + 3],
                              type_b4=d[30 + i*5 + 4]) for i in range(8)]
        p.pads_b = [PadConfig(note=d[70 + i*5],
                              type_b3=d[70 + i*5 + 3],
                              type_b4=d[70 + i*5 + 4]) for i in range(8)]
        p.knobs = []
        for i in range(8):
            off = 110 + i * 20
            name = bytes(d[off+4:off+20]).rstrip(b'\x00').decode('ascii', errors='?')
            p.knobs.append(KnobConfig(cc=d[off], min_val=d[off+1],
                                      max_val=d[off+2], mode=d[off+3], name=name))
        return p

    def to_dict(self) -> dict:
        return {
            "index": self.index, "name": self.name, "midi_channel": self.midi_channel,
            "arp_enabled": self.arp_enabled, "arp_mode": self.arp_mode,
            "arp_division": self.arp_division, "arp_octave": self.arp_octave,
            "arp_tempo": self.arp_tempo, "clock_source": self.clock_source,
            "pads_a": [{"note": p.note, "type_b3": p.type_b3, "type_b4": p.type_b4}
                       for p in self.pads_a],
            "pads_b": [{"note": p.note, "type_b3": p.type_b3, "type_b4": p.type_b4}
                       for p in self.pads_b],
            "knobs": [{"cc": k.cc, "min_val": k.min_val, "max_val": k.max_val,
                       "mode": k.mode, "name": k.name} for k in self.knobs],
            "_raw": list(self._raw) if self._raw else None,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Preset":
        p = cls(index=d.get("index", 0))
        p.name         = d.get("name", "USER")
        p.midi_channel = d.get("midi_channel", 1)
        p.arp_enabled  = d.get("arp_enabled", False)
        p.arp_mode     = d.get("arp_mode", 0)
        p.arp_division = d.get("arp_division", 2)
        p.arp_octave   = d.get("arp_octave", 0)
        p.arp_tempo    = d.get("arp_tempo", 120)
        p.clock_source = d.get("clock_source", 0)
        p.pads_a = [PadConfig(**x) for x in d.get("pads_a", [])] or p.pads_a
        p.pads_b = [PadConfig(**x) for x in d.get("pads_b", [])] or p.pads_b
        p.knobs  = [KnobConfig(**x) for x in d.get("knobs", [])] or p.knobs
        raw = d.get("_raw")
        p._raw = bytes(raw) if raw else None
        return p


class MPKMiniIV:
    """Handles ALSA MIDI I/O with the MPK mini IV (Software Control Port)."""

    MPK_PATTERNS = ["mpk mini iv", "mpk mini", "mpk"]

    def __init__(self):
        self._in  = rtmidi.MidiIn()
        self._out = rtmidi.MidiOut()
        self._in.ignore_types(sysex=False)
        self._sysex_buf: list = []
        self._sysex_cb:  Optional[Callable] = None
        self._midi_cb:   Optional[Callable] = None

    # ------------------------------------------------------------------ #
    # Port discovery
    # ------------------------------------------------------------------ #

    @classmethod
    def find_ports(cls, prefer_sysex: bool = True):
        """
        Return (in_ports, out_ports) for MPK mini IV.
        prefer_sysex=True  → Software Control Port for SysEx editor use
        prefer_sysex=False → MIDI Port for live note monitoring
        """
        mi = rtmidi.MidiIn(); mo = rtmidi.MidiOut()

        def _match(ports):
            all_m = [(i, n) for i, n in enumerate(ports)
                     if any(p in n.lower() for p in cls.MPK_PATTERNS)]
            if not all_m:
                return []
            if prefer_sysex:
                ctrl = [(i, n) for i, n in all_m if "software control" in n.lower()]
                return ctrl if ctrl else [all_m[0]]
            else:
                midi = [(i, n) for i, n in all_m if "midi port" in n.lower()]
                return midi if midi else [all_m[0]]

        ins  = _match(mi.get_ports())
        outs = _match(mo.get_ports())
        del mi, mo
        return ins, outs

    @classmethod
    def list_all_ports(cls):
        mi = rtmidi.MidiIn(); mo = rtmidi.MidiOut()
        r = list(enumerate(mi.get_ports())), list(enumerate(mo.get_ports()))
        del mi, mo
        return r

    def connect(self, in_port: int, out_port: int):
        self._in.open_port(in_port)
        self._out.open_port(out_port)
        self._in.set_callback(self._on_midi)

    def disconnect(self):
        if self._in.is_port_open():  self._in.close_port()
        if self._out.is_port_open(): self._out.close_port()

    def is_connected(self) -> bool:
        return self._in.is_port_open() and self._out.is_port_open()

    def set_sysex_callback(self, cb): self._sysex_cb = cb
    def set_midi_callback(self, cb):  self._midi_cb  = cb

    # ------------------------------------------------------------------ #
    # MIDI receive
    # ------------------------------------------------------------------ #

    def _on_midi(self, msg, _=None):
        raw, _ = msg
        if not raw: return
        if raw[0] == 0xF0:
            # rtmidi delivers complete SysEx in one shot when sysex=False is not set
            if 0xF7 in raw:
                if self._sysex_cb: self._sysex_cb(list(raw))
            else:
                # Rare: fragmented SysEx — buffer and accumulate
                self._sysex_buf = list(raw)
        elif self._sysex_buf:
            self._sysex_buf.extend(raw)
            if 0xF7 in self._sysex_buf:
                complete = self._sysex_buf[:]
                self._sysex_buf = []
                if self._sysex_cb: self._sysex_cb(complete)
        else:
            if self._midi_cb: self._midi_cb(raw)

    # ------------------------------------------------------------------ #
    # SysEx send
    # ------------------------------------------------------------------ #

    def _send(self, msg: list):
        if self._out.is_port_open():
            self._out.send_message(msg)

    def _build_sysex(self, cmd: int, data: list) -> list:
        n = len(data)
        return [0xF0, AKAI_MFR_ID, 0x00, MPK_DEVICE_ID, cmd,
                (n >> 7) & 0x7F, n & 0x7F] + data + [0xF7]

    def request_preset(self, index: int):
        """Ask device to send preset dump (index 0-3)."""
        self._send(self._build_sysex(CMD_GET_PRESET, [index & 0x03]))

    def send_preset(self, preset: Preset):
        """Push preset configuration to device."""
        payload = preset.to_sysex_payload()
        self._send(self._build_sysex(CMD_SET_PRESET, payload))

    def parse_sysex_response(self, data: list) -> Optional[Preset]:
        """Parse an incoming SysEx message, return Preset if it's a preset dump."""
        if (len(data) >= 7 and data[0] == 0xF0 and data[1] == AKAI_MFR_ID
                and data[3] == MPK_DEVICE_ID and data[4] == CMD_SET_PRESET):
            payload = data[7:-1]
            if len(payload) == PAYLOAD_LEN:
                return Preset.from_sysex_payload(payload)
        return None

    def create_virtual_port(self, name: str = "MPK mini IV (SelahOS)") -> rtmidi.MidiOut:
        """Open a virtual output port visible to all PipeWire/ALSA MIDI clients."""
        vo = rtmidi.MidiOut()
        vo.open_virtual_port(name)
        return vo
