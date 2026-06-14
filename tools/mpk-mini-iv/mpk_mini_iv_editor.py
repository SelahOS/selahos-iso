#!/usr/bin/env python3
"""
MPK mini IV Editor for SelahOS
Native replacement for the Windows 'Akai Professional MPK mini IV' editor.
Communicates via ALSA MIDI SysEx — works with PipeWire, JACK, and
SelahBridgePro Wine apps out of the box (no driver needed).
"""

import sys
import json
import os
from pathlib import Path
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QLabel, QComboBox, QSpinBox, QCheckBox, QPushButton,
    QGroupBox, QTabWidget, QStatusBar, QFrame, QSlider, QMessageBox,
    QFileDialog, QSplitter, QScrollArea,
)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QThread, pyqtSlot
from PyQt6.QtGui import QFont, QColor, QPalette, QIcon

from mpk_midi_core import (
    MPKMiniIV, Preset, PadConfig, KnobConfig, ArpConfig, GlobalConfig,
    ARP_MODES, ARP_DIVISIONS, ARP_OCTAVE_RGES, PAD_TYPES, KNOB_MODES,
    NUM_PADS, NUM_KNOBS,
)

CONFIG_DIR  = Path.home() / ".config" / "selah" / "mpk-mini-iv"
PRESET_EXT  = ".mpkpreset"
STYLE = """
QMainWindow, QWidget { background-color: #1e1e1e; color: #e0e0e0; }
QGroupBox {
    border: 1px solid #444; border-radius: 4px;
    margin-top: 8px; padding-top: 4px;
    font-weight: bold; color: #c0a0ff;
}
QGroupBox::title { subcontrol-origin: margin; left: 8px; }
QPushButton {
    background: #2d2d2d; border: 1px solid #555; border-radius: 3px;
    padding: 4px 10px; color: #e0e0e0;
}
QPushButton:hover { background: #3a3a3a; border-color: #888; }
QPushButton:pressed { background: #c0a0ff; color: #1e1e1e; }
QPushButton#sync_btn { background: #3a2060; border-color: #c0a0ff; color: #c0a0ff; font-weight: bold; }
QPushButton#sync_btn:hover { background: #c0a0ff; color: #1e1e1e; }
QComboBox, QSpinBox {
    background: #2d2d2d; border: 1px solid #555;
    border-radius: 3px; padding: 2px 4px; color: #e0e0e0;
}
QComboBox::drop-down { border: none; }
QTabWidget::pane { border: 1px solid #444; }
QTabBar::tab { background: #2d2d2d; color: #999; padding: 6px 12px; }
QTabBar::tab:selected { background: #3a2060; color: #c0a0ff; }
QLabel#pad_label {
    background: #2a1a40; border: 1px solid #7040a0;
    border-radius: 4px; padding: 4px; font-weight: bold;
    color: #c0a0ff; qproperty-alignment: AlignCenter;
}
QLabel#knob_label {
    background: #1a2a40; border: 1px solid #4070a0;
    border-radius: 18px; min-width: 36px; min-height: 36px;
    color: #80c0ff; qproperty-alignment: AlignCenter; font-weight: bold;
}
QCheckBox { color: #ccc; }
QCheckBox::indicator:checked { background: #c0a0ff; border: 1px solid #c0a0ff; border-radius: 2px; }
QStatusBar { background: #111; color: #888; font-size: 11px; }
QScrollArea { border: none; }
"""

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
def note_name(n: int) -> str:
    return f"{NOTE_NAMES[n % 12]}{(n // 12) - 1}"


class PadWidget(QGroupBox):
    changed = pyqtSignal()

    def __init__(self, index: int, parent=None):
        super().__init__(f"Pad {index + 1}", parent)
        self.index = index
        self._build()

    def _build(self):
        lay = QGridLayout(self)
        lay.setSpacing(4)

        self.lbl = QLabel(f"Pad {self.index + 1}", objectName="pad_label")
        lay.addWidget(self.lbl, 0, 0, 1, 2)

        lay.addWidget(QLabel("Note"), 1, 0)
        self.note = QSpinBox(); self.note.setRange(0, 127)
        self.note.setToolTip("MIDI note number (0-127)")
        lay.addWidget(self.note, 1, 1)

        lay.addWidget(QLabel("Ch"), 2, 0)
        self.channel = QSpinBox(); self.channel.setRange(1, 16)
        lay.addWidget(self.channel, 2, 1)

        lay.addWidget(QLabel("Vel"), 3, 0)
        self.velocity = QSpinBox(); self.velocity.setRange(1, 127)
        lay.addWidget(self.velocity, 3, 1)

        self.aftertouch = QCheckBox("Aftertouch")
        lay.addWidget(self.aftertouch, 4, 0, 1, 2)

        lay.addWidget(QLabel("Type"), 5, 0)
        self.pad_type = QComboBox()
        self.pad_type.addItems(PAD_TYPES)
        lay.addWidget(self.pad_type, 5, 1)

        for w in [self.note, self.channel, self.velocity,
                  self.aftertouch, self.pad_type]:
            w.installEventFilter(self)
        self.note.valueChanged.connect(self._on_change)
        self.channel.valueChanged.connect(self._on_change)
        self.velocity.valueChanged.connect(self._on_change)
        self.aftertouch.toggled.connect(self._on_change)
        self.pad_type.currentIndexChanged.connect(self._on_change)

    def _on_change(self):
        self.lbl.setToolTip(f"Note: {note_name(self.note.value())} ({self.note.value()})")
        self.changed.emit()

    def load(self, cfg: PadConfig):
        for w in [self.note, self.channel, self.velocity, self.pad_type]:
            w.blockSignals(True)
        self.aftertouch.blockSignals(True)
        self.note.setValue(cfg.note)
        self.channel.setValue(cfg.channel)
        self.velocity.setValue(cfg.velocity)
        self.aftertouch.setChecked(cfg.aftertouch)
        self.pad_type.setCurrentIndex(cfg.pad_type)
        for w in [self.note, self.channel, self.velocity, self.pad_type]:
            w.blockSignals(False)
        self.aftertouch.blockSignals(False)
        self.lbl.setToolTip(f"Note: {note_name(cfg.note)} ({cfg.note})")

    def get(self) -> PadConfig:
        return PadConfig(
            note=self.note.value(), channel=self.channel.value(),
            velocity=self.velocity.value(),
            aftertouch=self.aftertouch.isChecked(),
            pad_type=self.pad_type.currentIndex(),
        )


class KnobWidget(QGroupBox):
    changed = pyqtSignal()

    def __init__(self, index: int, parent=None):
        super().__init__(f"K{index + 1}", parent)
        self.index = index
        self._build()

    def _build(self):
        lay = QGridLayout(self)
        lay.setSpacing(3)

        self.lbl = QLabel(f"K{self.index + 1}", objectName="knob_label")
        lay.addWidget(self.lbl, 0, 0, 1, 2)

        lay.addWidget(QLabel("CC"), 1, 0)
        self.cc = QSpinBox(); self.cc.setRange(0, 127)
        lay.addWidget(self.cc, 1, 1)

        lay.addWidget(QLabel("Min"), 2, 0)
        self.min_val = QSpinBox(); self.min_val.setRange(0, 127)
        lay.addWidget(self.min_val, 2, 1)

        lay.addWidget(QLabel("Max"), 3, 0)
        self.max_val = QSpinBox(); self.max_val.setRange(0, 127)
        self.max_val.setValue(127)
        lay.addWidget(self.max_val, 3, 1)

        lay.addWidget(QLabel("Mode"), 4, 0)
        self.mode = QComboBox()
        self.mode.addItems(KNOB_MODES)
        lay.addWidget(self.mode, 4, 1)

        self.cc.valueChanged.connect(self.changed)
        self.min_val.valueChanged.connect(self.changed)
        self.max_val.valueChanged.connect(self.changed)
        self.mode.currentIndexChanged.connect(self.changed)

    def load(self, cfg: KnobConfig):
        for w in [self.cc, self.min_val, self.max_val, self.mode]:
            w.blockSignals(True)
        self.cc.setValue(cfg.cc)
        self.min_val.setValue(cfg.min_val)
        self.max_val.setValue(cfg.max_val)
        self.mode.setCurrentIndex(cfg.mode)
        for w in [self.cc, self.min_val, self.max_val, self.mode]:
            w.blockSignals(False)

    def get(self) -> KnobConfig:
        return KnobConfig(
            cc=self.cc.value(), min_val=self.min_val.value(),
            max_val=self.max_val.value(), mode=self.mode.currentIndex(),
        )


class ArpTab(QWidget):
    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._build()

    def _build(self):
        lay = QGridLayout(self)
        lay.setSpacing(8)

        self.enabled = QCheckBox("Arpeggiator Enabled")
        self.enabled.setStyleSheet("font-size:13px; font-weight:bold;")
        lay.addWidget(self.enabled, 0, 0, 1, 4)

        fields = [
            ("Mode", "mode", QComboBox, ARP_MODES),
            ("Division", "div", QComboBox, ARP_DIVISIONS),
            ("Octave Range", "oct", QComboBox, ARP_OCTAVE_RGES),
        ]
        for row, (lbl, attr, cls, items) in enumerate(fields, start=1):
            lay.addWidget(QLabel(lbl), row, 0)
            w = cls()
            w.addItems(items)
            setattr(self, attr, w)
            lay.addWidget(w, row, 1)

        lay.addWidget(QLabel("Tempo (BPM)"), 4, 0)
        self.tempo = QSpinBox(); self.tempo.setRange(20, 240); self.tempo.setValue(120)
        lay.addWidget(self.tempo, 4, 1)

        self.latch = QCheckBox("Latch")
        lay.addWidget(self.latch, 5, 0)

        lay.addWidget(QLabel("Clock"), 5, 2)
        self.clock = QComboBox(); self.clock.addItems(["Internal", "External"])
        lay.addWidget(self.clock, 5, 3)

        lay.setRowStretch(6, 1)

        for w in [self.enabled, self.mode, self.div, self.oct,
                  self.tempo, self.latch, self.clock]:
            if hasattr(w, 'toggled'):
                w.toggled.connect(self.changed)
            elif hasattr(w, 'currentIndexChanged'):
                w.currentIndexChanged.connect(self.changed)
            elif hasattr(w, 'valueChanged'):
                w.valueChanged.connect(self.changed)

    def load(self, cfg: ArpConfig):
        for w in [self.enabled, self.mode, self.div, self.oct,
                  self.tempo, self.latch, self.clock]:
            w.blockSignals(True)
        self.enabled.setChecked(cfg.enabled)
        self.mode.setCurrentIndex(cfg.mode)
        self.div.setCurrentIndex(cfg.division)
        self.oct.setCurrentIndex(cfg.octave_range)
        self.tempo.setValue(cfg.tempo)
        self.latch.setChecked(cfg.latch)
        self.clock.setCurrentIndex(cfg.clock_source)
        for w in [self.enabled, self.mode, self.div, self.oct,
                  self.tempo, self.latch, self.clock]:
            w.blockSignals(False)

    def get(self) -> ArpConfig:
        return ArpConfig(
            enabled=self.enabled.isChecked(),
            mode=self.mode.currentIndex(),
            division=self.div.currentIndex(),
            octave_range=self.oct.currentIndex(),
            latch=self.latch.isChecked(),
            tempo=self.tempo.value(),
            clock_source=self.clock.currentIndex(),
        )


class GlobalTab(QWidget):
    changed = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._build()

    def _build(self):
        lay = QGridLayout(self)
        lay.setSpacing(8)

        lay.addWidget(QLabel("MIDI Channel"), 0, 0)
        self.channel = QSpinBox(); self.channel.setRange(1, 16)
        lay.addWidget(self.channel, 0, 1)

        lay.addWidget(QLabel("Transpose (semitones)"), 1, 0)
        self.transpose = QSpinBox(); self.transpose.setRange(-12, 12)
        lay.addWidget(self.transpose, 1, 1)

        lay.addWidget(QLabel("Pitchbend Range"), 2, 0)
        self.pb_range = QSpinBox(); self.pb_range.setRange(1, 12)
        lay.addWidget(self.pb_range, 2, 1)

        self.aftertouch = QCheckBox("Global Aftertouch")
        lay.addWidget(self.aftertouch, 3, 0, 1, 2)

        lay.addWidget(QLabel("Sustain Polarity"), 4, 0)
        self.sustain_pol = QComboBox()
        self.sustain_pol.addItems(["Normal", "Inverted"])
        lay.addWidget(self.sustain_pol, 4, 1)

        lay.setRowStretch(5, 1)

        for w in [self.channel, self.transpose, self.pb_range,
                  self.aftertouch, self.sustain_pol]:
            if hasattr(w, 'toggled'):
                w.toggled.connect(self.changed)
            elif hasattr(w, 'currentIndexChanged'):
                w.currentIndexChanged.connect(self.changed)
            elif hasattr(w, 'valueChanged'):
                w.valueChanged.connect(self.changed)

    def load(self, cfg: GlobalConfig):
        for w in [self.channel, self.transpose, self.pb_range,
                  self.aftertouch, self.sustain_pol]:
            w.blockSignals(True)
        self.channel.setValue(cfg.channel)
        self.transpose.setValue(cfg.transpose)
        self.pb_range.setValue(cfg.pitchbend_range)
        self.aftertouch.setChecked(cfg.aftertouch)
        self.sustain_pol.setCurrentIndex(cfg.sustain_polarity)
        for w in [self.channel, self.transpose, self.pb_range,
                  self.aftertouch, self.sustain_pol]:
            w.blockSignals(False)

    def get(self) -> GlobalConfig:
        return GlobalConfig(
            channel=self.channel.value(),
            transpose=self.transpose.value(),
            pitchbend_range=self.pb_range.value(),
            aftertouch=self.aftertouch.isChecked(),
            sustain_polarity=self.sustain_pol.currentIndex(),
        )


class DeviceMonitorThread(QThread):
    """Background thread: polls for device connection and incoming MIDI."""
    device_connected    = pyqtSignal(int, str, int, str)  # in_port, in_name, out_port, out_name
    device_disconnected = pyqtSignal()
    sysex_received      = pyqtSignal(list)
    midi_received       = pyqtSignal(list)

    def __init__(self, device: MPKMiniIV, parent=None):
        super().__init__(parent)
        self._device = device
        self._running = True
        self._connected = False

    def run(self):
        import rtmidi
        self._device.set_sysex_callback(lambda d: self.sysex_received.emit(d))
        self._device.set_midi_callback(lambda d: self.midi_received.emit(d))
        while self._running:
            ins, outs = MPKMiniIV.find_mpk_ports()
            if ins and outs and not self._connected:
                in_port, in_name   = ins[0]
                out_port, out_name = outs[0]
                self._device.connect(in_port, out_port)
                self._connected = True
                self.device_connected.emit(in_port, in_name, out_port, out_name)
            elif not ins and self._connected:
                self._device.disconnect()
                self._connected = False
                self.device_disconnected.emit()
            self.msleep(1500)

    def stop(self):
        self._running = False
        self.wait()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MPK mini IV Editor — SelahOS")
        self.setMinimumSize(900, 680)

        self._device  = MPKMiniIV()
        self._presets = [Preset(index=i) for i in range(4)]
        self._current_preset = 0
        self._dirty   = False
        self._monitor = DeviceMonitorThread(self._device)
        self._virtual_out = None

        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self._load_local_presets()
        self._build_ui()
        self._apply_style()
        self._connect_monitor()
        self._monitor.start()
        self._load_preset_to_ui(0)

    # ------------------------------------------------------------------ #
    # UI construction
    # ------------------------------------------------------------------ #

    def _build_ui(self):
        cw = QWidget(); self.setCentralWidget(cw)
        root = QVBoxLayout(cw); root.setSpacing(8); root.setContentsMargins(10, 10, 10, 6)

        # --- Top bar ---
        top = QHBoxLayout()
        self._conn_lbl = QLabel("● Not connected")
        self._conn_lbl.setStyleSheet("color:#f44; font-weight:bold;")
        top.addWidget(self._conn_lbl)

        top.addStretch()
        top.addWidget(QLabel("Preset:"))
        self._preset_sel = QComboBox()
        self._preset_sel.addItems(["1", "2", "3", "4"])
        self._preset_sel.currentIndexChanged.connect(self._on_preset_changed)
        top.addWidget(self._preset_sel)

        self._get_btn  = QPushButton("Get from Device")
        self._send_btn = QPushButton("Send to Device", objectName="sync_btn")
        self._get_btn.clicked.connect(self._on_get)
        self._send_btn.clicked.connect(self._on_send)
        top.addWidget(self._get_btn)
        top.addWidget(self._send_btn)
        root.addLayout(top)

        # --- Pad grid ---
        pad_group = QGroupBox("Pads")
        pad_lay = QGridLayout(pad_group)
        self._pads = []
        for i in range(NUM_PADS):
            pw = PadWidget(i)
            pw.changed.connect(self._mark_dirty)
            pad_lay.addWidget(pw, i // 4, i % 4)
            self._pads.append(pw)
        root.addWidget(pad_group)

        # --- Knob grid ---
        knob_group = QGroupBox("Knobs")
        knob_lay = QGridLayout(knob_group)
        self._knobs = []
        for i in range(NUM_KNOBS):
            kw = KnobWidget(i)
            kw.changed.connect(self._mark_dirty)
            knob_lay.addWidget(kw, 0, i)
            self._knobs.append(kw)
        root.addWidget(knob_group)

        # --- Tabs: Arpeggiator / Global / MIDI Routing ---
        tabs = QTabWidget()
        self._arp_tab    = ArpTab()
        self._global_tab = GlobalTab()
        self._routing_tab = self._build_routing_tab()
        self._arp_tab.changed.connect(self._mark_dirty)
        self._global_tab.changed.connect(self._mark_dirty)
        tabs.addTab(self._arp_tab,     "Arpeggiator")
        tabs.addTab(self._global_tab,  "Global")
        tabs.addTab(self._routing_tab, "MIDI Routing")
        root.addWidget(tabs)

        # --- Bottom bar ---
        bot = QHBoxLayout()
        save_btn = QPushButton("Save Preset File…")
        load_btn = QPushButton("Load Preset File…")
        save_btn.clicked.connect(self._on_save_file)
        load_btn.clicked.connect(self._on_load_file)
        self._dirty_lbl = QLabel("")
        self._dirty_lbl.setStyleSheet("color:#f0a000;")
        bot.addWidget(save_btn)
        bot.addWidget(load_btn)
        bot.addStretch()
        bot.addWidget(self._dirty_lbl)
        root.addLayout(bot)

        self.setStatusBar(QStatusBar())
        self.statusBar().showMessage("Ready — plug in MPK mini IV to connect")

    def _build_routing_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)

        info = QLabel(
            "The MPK mini IV is class-compliant — it appears in ALSA/PipeWire automatically.\n"
            "Use PipeWire patchbay (Helvum / Patchance) or aconnect to route MIDI.\n\n"
            "SelahBridgePro: Wine DAWs see MIDI via WineMIDI → PipeWire bridge.\n"
            "No extra routing is needed — plug in and play."
        )
        info.setWordWrap(True)
        info.setStyleSheet("color:#aaa; padding:8px;")
        lay.addWidget(info)

        self._vport_btn = QPushButton("Create Virtual Port: 'MPK mini IV (SelahOS)'")
        self._vport_btn.clicked.connect(self._on_create_virtual_port)
        lay.addWidget(self._vport_btn)

        self._vport_status = QLabel("Virtual port: not created")
        self._vport_status.setStyleSheet("color:#888;")
        lay.addWidget(self._vport_status)

        lay.addStretch()

        tip = QLabel(
            "To connect to a native app:\n"
            "  aconnect 'MPK mini IV' 'your-app-port'\n\n"
            "To connect inside SelahBridgePro (Wine):\n"
            "  The Wine app sees MIDI ports via the WineASIO MIDI bridge."
        )
        tip.setStyleSheet("color:#666; font-size:11px;")
        tip.setWordWrap(True)
        lay.addWidget(tip)
        return w

    def _apply_style(self):
        self.setStyleSheet(STYLE)

    # ------------------------------------------------------------------ #
    # Device monitor
    # ------------------------------------------------------------------ #

    def _connect_monitor(self):
        self._monitor.device_connected.connect(self._on_connected)
        self._monitor.device_disconnected.connect(self._on_disconnected)
        self._monitor.sysex_received.connect(self._on_sysex)

    @pyqtSlot(int, str, int, str)
    def _on_connected(self, in_port, in_name, out_port, out_name):
        self._conn_lbl.setText(f"● {in_name}")
        self._conn_lbl.setStyleSheet("color:#44ff88; font-weight:bold;")
        self.statusBar().showMessage(f"Connected: {in_name}")
        self._get_btn.setEnabled(True)
        self._send_btn.setEnabled(True)

    @pyqtSlot()
    def _on_disconnected(self):
        self._conn_lbl.setText("● Not connected")
        self._conn_lbl.setStyleSheet("color:#f44; font-weight:bold;")
        self.statusBar().showMessage("MPK mini IV disconnected")

    @pyqtSlot(list)
    def _on_sysex(self, data: list):
        if len(data) < 7:
            return
        if data[1] != 0x47:
            return
        cmd = data[4]
        payload = data[7:-1]
        if cmd in (0x67, 0x66):
            idx = self._current_preset
            if payload and payload[0] < 4:
                idx = payload[0]
            self._presets[idx] = Preset.from_sysex_data(payload, idx)
            if idx == self._current_preset:
                self._load_preset_to_ui(idx)
            self.statusBar().showMessage(f"Received preset {idx + 1} from device")
            self._save_local_presets()

    # ------------------------------------------------------------------ #
    # Preset UI
    # ------------------------------------------------------------------ #

    def _on_preset_changed(self, index: int):
        self._save_ui_to_preset(self._current_preset)
        self._current_preset = index
        self._load_preset_to_ui(index)

    def _load_preset_to_ui(self, index: int):
        p = self._presets[index]
        for i, pw in enumerate(self._pads):
            pw.load(p.pads[i])
        for i, kw in enumerate(self._knobs):
            kw.load(p.knobs[i])
        self._arp_tab.load(p.arp)
        self._global_tab.load(p.globals)
        self._dirty = False
        self._dirty_lbl.setText("")

    def _save_ui_to_preset(self, index: int):
        p = self._presets[index]
        p.pads   = [pw.get() for pw in self._pads]
        p.knobs  = [kw.get() for kw in self._knobs]
        p.arp    = self._arp_tab.get()
        p.globals = self._global_tab.get()

    def _mark_dirty(self):
        self._dirty = True
        self._dirty_lbl.setText("Unsaved changes")

    # ------------------------------------------------------------------ #
    # Device actions
    # ------------------------------------------------------------------ #

    def _on_get(self):
        if not self._device.is_connected():
            self._show_no_device(); return
        self._device.request_preset(self._current_preset)
        self.statusBar().showMessage(f"Requested preset {self._current_preset + 1}…")

    def _on_send(self):
        if not self._device.is_connected():
            self._show_no_device(); return
        self._save_ui_to_preset(self._current_preset)
        self._device.send_preset(self._presets[self._current_preset])
        self._dirty = False
        self._dirty_lbl.setText("")
        self._save_local_presets()
        self.statusBar().showMessage(f"Sent preset {self._current_preset + 1} to device")

    def _on_create_virtual_port(self):
        if self._virtual_out:
            self._vport_status.setText("Virtual port already active")
            return
        self._virtual_out = self._device.create_virtual_port()
        self._vport_status.setText("✓ Virtual port active: 'MPK mini IV (SelahOS)'")
        self._vport_status.setStyleSheet("color:#44ff88;")
        self.statusBar().showMessage("Virtual MIDI port created — visible to all apps via PipeWire/ALSA")

    def _show_no_device(self):
        QMessageBox.warning(self, "Not Connected",
                            "No MPK mini IV detected.\nPlug in the device and wait for auto-connect.")

    # ------------------------------------------------------------------ #
    # File I/O
    # ------------------------------------------------------------------ #

    def _on_save_file(self):
        self._save_ui_to_preset(self._current_preset)
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Preset", str(CONFIG_DIR),
            f"MPK mini IV Preset (*{PRESET_EXT})")
        if not path:
            return
        if not path.endswith(PRESET_EXT):
            path += PRESET_EXT
        p = self._presets[self._current_preset]
        data = {
            "index": p.index,
            "pads":  [vars(pd) for pd in p.pads],
            "knobs": [vars(k) for k in p.knobs],
            "arp":   vars(p.arp),
            "globals": vars(p.globals),
        }
        Path(path).write_text(json.dumps(data, indent=2))
        self.statusBar().showMessage(f"Saved: {path}")

    def _on_load_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Load Preset", str(CONFIG_DIR),
            f"MPK mini IV Preset (*{PRESET_EXT})")
        if not path:
            return
        try:
            data = json.loads(Path(path).read_text())
            p = Preset(index=self._current_preset)
            p.pads   = [PadConfig(**pd) for pd in data.get("pads", [])]
            p.knobs  = [KnobConfig(**k) for k in data.get("knobs", [])]
            p.arp    = ArpConfig(**data.get("arp", {}))
            p.globals = GlobalConfig(**data.get("globals", {}))
            self._presets[self._current_preset] = p
            self._load_preset_to_ui(self._current_preset)
            self.statusBar().showMessage(f"Loaded: {path}")
        except Exception as e:
            QMessageBox.critical(self, "Load Error", str(e))

    # ------------------------------------------------------------------ #
    # Persist presets locally (survives app restart, even without device)
    # ------------------------------------------------------------------ #

    def _local_preset_path(self) -> Path:
        return CONFIG_DIR / "presets.json"

    def _save_local_presets(self):
        self._save_ui_to_preset(self._current_preset)
        data = []
        for p in self._presets:
            data.append({
                "index": p.index,
                "pads":  [vars(pd) for pd in p.pads],
                "knobs": [vars(k) for k in p.knobs],
                "arp":   vars(p.arp),
                "globals": vars(p.globals),
            })
        self._local_preset_path().write_text(json.dumps(data, indent=2))

    def _load_local_presets(self):
        path = self._local_preset_path()
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text())
            for i, d in enumerate(data[:4]):
                p = Preset(index=i)
                p.pads   = [PadConfig(**pd) for pd in d.get("pads", [])]
                p.knobs  = [KnobConfig(**k) for k in d.get("knobs", [])]
                p.arp    = ArpConfig(**d.get("arp", {}))
                p.globals = GlobalConfig(**d.get("globals", {}))
                self._presets[i] = p
        except Exception:
            pass

    def closeEvent(self, event):
        self._save_local_presets()
        self._monitor.stop()
        self._device.disconnect()
        super().closeEvent(event)


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("MPK mini IV Editor")
    app.setOrganizationName("Selah Technologies")
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
