#!/usr/bin/env python3
"""
SelahOS MPC Studio 2 Editor
Professional control editor for Akai Professional MPC Studio mk2
Designed to match MPK mini IV editor aesthetic and functionality
"""

import sys
import json
import time
from pathlib import Path
from typing import Optional, Dict, List

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QTabWidget, QLabel, QPushButton, QSlider, QSpinBox, QComboBox,
        QGridLayout, QFrame, QStatusBar, QMessageBox
    )
    from PyQt6.QtCore import Qt, QTimer, QSize
    from PyQt6.QtGui import QColor, QFont, QIcon, QPixmap
except ImportError:
    print("ERROR: PyQt6 not found")
    print("Install with: pip install PyQt6")
    sys.exit(1)

try:
    import mido
except ImportError:
    print("ERROR: python-mido not found")
    print("Install with: pip install python-mido")
    sys.exit(1)


# Real MPC Studio 2 pad -> raw MIDI note map, pad 1..16 (bottom row first),
# confirmed empirically by selah-mpc-bridge (see MPC_STUDIO2_PAD_NOTES in
# /usr/local/bin/selah-mpc-bridge). The bridge listens on pad_channel=10
# (0-indexed 9) and exposes decoded pad hits on its "SelahMPC" virtual port,
# and forwards whatever we send to "SelahMPC Feedback" straight to the pad
# LEDs on feedback_channel=1 (0-indexed 0).
MPC_PAD_NOTES = [
    37, 36, 42, 82,   # pads  1- 4 (bottom row)
    40, 38, 46, 44,   # pads  5- 8
    48, 47, 45, 43,   # pads  9-12
    49, 55, 51, 53,   # pads 13-16 (top row)
]
PAD_NUM_TO_NOTE = {i + 1: note for i, note in enumerate(MPC_PAD_NOTES)}
NOTE_TO_PAD_NUM = {note: i + 1 for i, note in enumerate(MPC_PAD_NOTES)}
PAD_MIDI_CHANNEL = 9       # 0-indexed (bridge "pad_channel = 10")
FEEDBACK_MIDI_CHANNEL = 0  # 0-indexed (bridge "feedback_channel = 1")


class SelahOSStyle:
    """SelahOS color scheme and styling"""

    # Colors
    PRIMARY = "#1e1e1e"          # Dark background
    SECONDARY = "#2a2a2a"        # Slightly lighter
    ACCENT = "#D4AF37"           # Gold/orange
    TEXT_PRIMARY = "#ffffff"     # White text
    TEXT_SECONDARY = "#888888"   # Gray text
    DANGER = "#ff4444"           # Red for disconnected
    SUCCESS = "#44ff44"          # Green for connected

    # Fonts
    FONT_FAMILY = "Arial"
    FONT_SIZE_TITLE = 16
    FONT_SIZE_NORMAL = 11
    FONT_SIZE_SMALL = 9


class PadGrid(QWidget):
    """Visual representation of MPC Studio 2 pads (4x4 grid with RGB)"""

    # Pad labels matching hardware
    PAD_LABELS = {
        1: "TRACK\nVIEW", 2: "GRID", 3: "WAVE", 4: "LIST\nEDIT",
        5: "SAMPLE\nEDIT", 6: "PROG\nEDIT", 7: "PAD\nMIXER", 8: "CH\nMIXER",
        9: "NEXT\nSEQ", 10: "SONG", 11: "MIDI\nCTRL", 12: "MEDIA",
        13: "SAMPLER", 14: "LOOPER", 15: "STEP\nSEQ", 16: "SAVE"
    }

    # RGB neon colors for each pad (matching hardware)
    PAD_COLORS = {
        1: "#ff0000",   # Red
        2: "#ffff00",   # Yellow
        3: "#ff8800",   # Orange
        4: "#ff8800",   # Orange
        5: "#00ff00",   # Green
        6: "#ffffff",   # White
        7: "#00ffff",   # Cyan
        8: "#ff8800",   # Orange
        9: "#0088ff",   # Blue
        10: "#0088ff",  # Blue
        11: "#ffaa00",  # Orange/Peach
        12: "#00ffff",  # Cyan
        13: "#ff00ff",  # Magenta/Purple
        14: "#0088ff",  # Blue
        15: "#0088ff",  # Blue
        16: "#ff00ff"   # Magenta/Purple
    }

    def __init__(self, parent=None, on_pad_event=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSStyle.PRIMARY};")

        # Callback(pad_num: int, is_down: bool) fired on press/release so the
        # owning window can forward real MIDI to the device via the bridge.
        self.on_pad_event = on_pad_event

        layout = QGridLayout()
        layout.setSpacing(12)
        layout.setContentsMargins(30, 30, 30, 30)

        self.pads = {}
        self.pad_colors = {}

        # Create 4x4 grid of pads. Hardware numbers pads 1-4 on the BOTTOM
        # row going up to 13-16 on the TOP row, so row 0 (top of the Qt
        # grid) must hold pads 13-16, not 1-4.
        for row in range(4):
            for col in range(4):
                pad_num = (3 - row) * 4 + col + 1
                pad = self._create_pad_button(pad_num)
                self.pads[pad_num] = pad
                # This is the pad's *current* color (used by flash_pad), not
                # a "no color yet" placeholder -- it must start as the real
                # hardware color or the pad goes invisible the instant it's
                # touched (border == background == near-black).
                self.pad_colors[pad_num] = self.PAD_COLORS.get(pad_num, SelahOSStyle.ACCENT)
                layout.addWidget(pad, row, col)

        self.setLayout(layout)

    def _pad_stylesheet(self, color: str, lit: bool = False) -> str:
        """Stylesheet for a pad, optionally in its 'lit' (active) state."""
        bg = color if lit else "#0a0a0a"
        fg = "#000000" if lit else color
        hover_bg = color if lit else "#1a1a1a"
        return f"""
            QPushButton {{
                background-color: {bg};
                color: {fg};
                border: 3px solid {color};
                border-radius: 8px;
                font-weight: bold;
                font-size: 10px;
                padding: 4px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: {hover_bg};
                border: 3px solid {color};
            }}
            QPushButton:pressed {{
                background-color: {color};
                color: #000000;
                border: 3px solid {color};
            }}
        """

    def _create_pad_button(self, pad_num: int) -> QPushButton:
        """Create a single pad button with label"""
        label = self.PAD_LABELS.get(pad_num, f"PAD {pad_num}")
        btn = QPushButton(label)
        btn.setFixedSize(QSize(100, 100))
        btn.pad_num = pad_num

        color = self.PAD_COLORS.get(pad_num, SelahOSStyle.ACCENT)
        btn.setStyleSheet(self._pad_stylesheet(color, lit=False))

        btn.pressed.connect(lambda p=pad_num: self._on_pad_pressed(p))
        btn.released.connect(lambda p=pad_num: self._on_pad_released(p))
        return btn

    def _on_pad_pressed(self, pad_num: int):
        """Pad pressed in the UI: light it immediately, then forward out."""
        self.flash_pad(pad_num, lit=True)
        if self.on_pad_event:
            self.on_pad_event(pad_num, True)

    def _on_pad_released(self, pad_num: int):
        self.flash_pad(pad_num, lit=False)
        if self.on_pad_event:
            self.on_pad_event(pad_num, False)

    def flash_pad(self, pad_num: int, lit: bool):
        """Set a pad's visual lit/unlit state (used for real-time feedback)."""
        btn = self.pads.get(pad_num)
        if not btn:
            return
        color = self.pad_colors.get(pad_num) or self.PAD_COLORS.get(pad_num, SelahOSStyle.ACCENT)
        btn.setStyleSheet(self._pad_stylesheet(color, lit=lit))

    def set_pad_color(self, pad_num: int, color: str):
        """Set RGB color for a pad (HEX format)"""
        if pad_num in self.pads:
            self.pad_colors[pad_num] = color
            self.pads[pad_num].setStyleSheet(self._pad_stylesheet(color, lit=False))


class TransportControls(QWidget):
    """Transport buttons (Play, Stop, Record, etc.)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSStyle.SECONDARY};")

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(10)

        # Transport buttons
        buttons = [
            ("⏮ Prev", "Previous"),
            ("⏪ Rwd", "Rewind"),
            ("▶ Play", "Play"),
            ("⏸ Stop", "Stop"),
            ("⏺ Record", "Record"),
            ("⏭ Next", "Next"),
        ]

        self.transport_btns = {}

        for label, name in buttons:
            btn = QPushButton(label)
            btn.setMinimumHeight(50)
            btn.setMinimumWidth(80)
            btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: #1a1a1a;
                    color: {SelahOSStyle.ACCENT};
                    border: 2px solid {SelahOSStyle.ACCENT};
                    border-radius: 4px;
                    font-weight: bold;
                    font-size: 10px;
                }}
                QPushButton:hover {{
                    background-color: #2a2a2a;
                }}
                QPushButton:pressed {{
                    background-color: #3a3a3a;
                    border: 2px solid {SelahOSStyle.SUCCESS};
                }}
            """)

            layout.addWidget(btn)
            self.transport_btns[name] = btn

        self.setLayout(layout)


class MPCStudio2Editor(QMainWindow):
    """SelahOS MPC Studio 2 Editor - Main Application Window"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("MPC Studio 2 — SelahOS")
        self.setGeometry(100, 100, 1200, 1000)

        # Try to load device profile
        self.device_profile = self._load_device_profile()
        self.midi_device = None
        self.connection_status = False   # raw MPC Studio 2 USB device seen?
        self.bridge_status = False       # selah-mpc-bridge virtual ports up?

        # Real MIDI I/O through the selah-mpc-bridge daemon, NOT the raw
        # device ports directly (the raw protocol needs a handshake the
        # bridge already handles). "SelahMPC" = decoded pad hits (in),
        # "SelahMPC Feedback" = pad LED control (out).
        self._midi_in_pads = None
        self._midi_out_leds = None
        self.pad_grids: List[PadGrid] = []

        # Setup UI
        self._setup_ui()
        self._setup_styles()

        # Connection timer
        self.check_timer = QTimer()
        self.check_timer.timeout.connect(self._check_connection)
        self.check_timer.start(1000)  # Check every second

        # Poll the bridge for real pad hits (non-blocking)
        self.midi_poll_timer = QTimer()
        self.midi_poll_timer.timeout.connect(self._poll_pad_input)
        self.midi_poll_timer.start(30)

    def _load_device_profile(self) -> Dict:
        """Load device profile from JSON"""
        profile_path = Path(__file__).parent / "profiles" / "mpc_studio2_mk2.json"

        if profile_path.exists():
            with open(profile_path, 'r') as f:
                return json.load(f)

        # Fallback default profile
        return {
            "device": {
                "name": "Akai Professional MPC Studio mk2",
                "usb_vid": "09E8",
                "usb_pid": "004A"
            },
            "pads": {"count": 16},
            "controls": {}
        }

    def _setup_ui(self):
        """Build the user interface"""
        # Central widget
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Header
        header = self._create_header()
        main_layout.addWidget(header)

        # Tab widget
        tabs = self._create_tabs()
        main_layout.addWidget(tabs)

        # Status bar
        self.status_label = QLabel("Waiting for MPC Studio 2...")
        self.status_label.setStyleSheet(f"""
            background-color: {SelahOSStyle.PRIMARY};
            color: {SelahOSStyle.DANGER};
            padding: 8px;
            font-weight: bold;
        """)
        main_layout.addWidget(self.status_label)

        central.setLayout(main_layout)

    def _create_header(self) -> QWidget:
        """Create the header with title and controls"""
        header = QWidget()
        header.setStyleSheet(f"background-color: {SelahOSStyle.PRIMARY};")
        header.setMaximumHeight(80)

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 15, 20, 15)

        # Logo and title
        title_layout = QVBoxLayout()

        logo_label = QLabel("SELAH")
        logo_label.setStyleSheet(f"""
            color: {SelahOSStyle.ACCENT};
            font-size: 14px;
            font-weight: bold;
            letter-spacing: 2px;
        """)
        title_layout.addWidget(logo_label)

        title_label = QLabel("MPC Studio 2 Editor")
        title_label.setStyleSheet(f"""
            color: {SelahOSStyle.TEXT_PRIMARY};
            font-size: 18px;
            font-weight: bold;
        """)
        title_layout.addWidget(title_label)

        layout.addLayout(title_layout)
        layout.addStretch()

        # Connection status
        connection_layout = QVBoxLayout()

        connection_label = QLabel("● Not connected")
        connection_label.setStyleSheet(f"""
            color: {SelahOSStyle.DANGER};
            font-weight: bold;
            font-size: 11px;
        """)
        self.connection_label = connection_label
        connection_layout.addWidget(connection_label)

        # Control buttons
        btn_layout = QHBoxLayout()

        btn_sync = QPushButton("Sync All ⟳")
        btn_sync.setStyleSheet(self._button_style())
        btn_sync.clicked.connect(self._on_sync)
        btn_layout.addWidget(btn_sync)

        btn_get = QPushButton("Get Preset")
        btn_get.setStyleSheet(self._button_style())
        btn_get.clicked.connect(self._on_get_preset)
        btn_layout.addWidget(btn_get)

        btn_send = QPushButton("Send Preset")
        btn_send.setStyleSheet(self._button_style())
        btn_send.clicked.connect(self._on_send_preset)
        btn_layout.addWidget(btn_send)

        connection_layout.addLayout(btn_layout)

        layout.addLayout(connection_layout)

        header.setLayout(layout)
        return header

    def _create_tabs(self) -> QTabWidget:
        """Create tab widget with different control sections"""
        tabs = QTabWidget()
        tabs.setStyleSheet(f"""
            QTabWidget {{
                background-color: {SelahOSStyle.PRIMARY};
            }}
            QTabBar::tab {{
                background-color: {SelahOSStyle.SECONDARY};
                color: {SelahOSStyle.TEXT_SECONDARY};
                padding: 8px 20px;
                border: 1px solid {SelahOSStyle.SECONDARY};
            }}
            QTabBar::tab:selected {{
                color: {SelahOSStyle.ACCENT};
                border-bottom: 2px solid {SelahOSStyle.ACCENT};
            }}
            QTabWidget::pane {{
                border: none;
                background-color: {SelahOSStyle.PRIMARY};
            }}
        """)

        # Controller tab (main view)
        controller_tab = QWidget()
        controller_tab.setStyleSheet(f"background-color: {SelahOSStyle.PRIMARY};")
        controller_layout = QVBoxLayout()
        controller_layout.setContentsMargins(10, 10, 10, 10)
        controller_layout.setSpacing(15)

        # Title
        title = QLabel("MPC Studio 2 — Live Controller View")
        title.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold;")
        controller_layout.addWidget(title)

        # Pad grid
        pad_grid = PadGrid(on_pad_event=self._on_pad_event)
        self.pad_grids.append(pad_grid)
        controller_layout.addWidget(pad_grid, 1)

        # Transport controls
        transport = TransportControls()
        controller_layout.addWidget(transport)

        # Preset section
        preset_frame = QFrame()
        preset_frame.setStyleSheet(f"""
            QFrame {{
                background-color: {SelahOSStyle.SECONDARY};
                border: 1px solid {SelahOSStyle.ACCENT};
                border-radius: 4px;
            }}
        """)
        preset_layout = QHBoxLayout()
        preset_layout.setContentsMargins(20, 15, 20, 15)

        preset_label = QLabel("PRESET 1")
        preset_label.setStyleSheet(f"""
            color: {SelahOSStyle.ACCENT};
            font-weight: bold;
            min-width: 150px;
            padding: 10px;
            background-color: {SelahOSStyle.PRIMARY};
            border: 1px solid {SelahOSStyle.ACCENT};
            border-radius: 3px;
        """)
        preset_layout.addWidget(preset_label)

        preset_layout.addStretch()

        # Preset buttons
        btn_save = QPushButton("Save Preset...")
        btn_save.setStyleSheet(self._button_style(small=True))
        preset_layout.addWidget(btn_save)

        btn_load = QPushButton("Load Preset...")
        btn_load.setStyleSheet(self._button_style(small=True))
        preset_layout.addWidget(btn_load)

        preset_frame.setLayout(preset_layout)
        controller_layout.addWidget(preset_frame)

        controller_tab.setLayout(controller_layout)
        tabs.addTab(controller_tab, "Controller")

        # Pads tab
        pads_tab = QWidget()
        pads_layout = QVBoxLayout()
        title_pads = QLabel("Pad Configuration (16 Pads)")
        title_pads.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold; padding: 20px;")
        pads_layout.addWidget(title_pads)
        pads_grid = PadGrid(on_pad_event=self._on_pad_event)
        self.pad_grids.append(pads_grid)
        pads_layout.addWidget(pads_grid)
        pads_tab.setLayout(pads_layout)
        tabs.addTab(pads_tab, "Pads")

        # Transport tab
        transport_tab = QWidget()
        transport_layout = QVBoxLayout()
        title_transport = QLabel("Transport Controls")
        title_transport.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold; padding: 20px;")
        transport_layout.addWidget(title_transport)
        transport_layout.addWidget(TransportControls())
        transport_layout.addStretch()
        transport_tab.setLayout(transport_layout)
        tabs.addTab(transport_tab, "Transport")

        # Controls tab
        controls_tab = QWidget()
        controls_layout = QVBoxLayout()
        controls_layout.setContentsMargins(20, 20, 20, 20)
        title_controls = QLabel("MPC Studio 2 Controls & Routing")
        title_controls.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold;")
        controls_layout.addWidget(title_controls)

        info_label = QLabel(
            "Jog Wheel | Faders | Buttons | Deck Mode\n\n"
            "Configure control mapping and MIDI routing below."
        )
        info_label.setStyleSheet(f"color: {SelahOSStyle.TEXT_SECONDARY}; padding: 20px;")
        controls_layout.addWidget(info_label)
        controls_layout.addStretch()
        controls_tab.setLayout(controls_layout)
        tabs.addTab(controls_tab, "Controls")

        # Global tab
        global_tab = QWidget()
        global_layout = QVBoxLayout()
        global_layout.setContentsMargins(20, 20, 20, 20)
        title_global = QLabel("Global Settings")
        title_global.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold;")
        global_layout.addWidget(title_global)

        # Settings options
        settings_frame = QFrame()
        settings_frame.setStyleSheet(f"""
            QFrame {{
                background-color: {SelahOSStyle.SECONDARY};
                border: 1px solid {SelahOSStyle.SECONDARY};
                border-radius: 4px;
            }}
        """)
        settings_layout = QVBoxLayout()
        settings_layout.setContentsMargins(20, 20, 20, 20)

        # Tempo
        tempo_layout = QHBoxLayout()
        tempo_label = QLabel("Tempo (BPM):")
        tempo_label.setStyleSheet(f"color: {SelahOSStyle.TEXT_PRIMARY};")
        tempo_spin = QSpinBox()
        tempo_spin.setRange(20, 300)
        tempo_spin.setValue(120)
        tempo_spin.setStyleSheet(self._input_style())
        tempo_layout.addWidget(tempo_label)
        tempo_layout.addWidget(tempo_spin)
        tempo_layout.addStretch()
        settings_layout.addLayout(tempo_layout)

        # MIDI Channel
        channel_layout = QHBoxLayout()
        channel_label = QLabel("MIDI Channel:")
        channel_label.setStyleSheet(f"color: {SelahOSStyle.TEXT_PRIMARY};")
        channel_combo = QComboBox()
        channel_combo.addItems([f"Channel {i+1}" for i in range(16)])
        channel_combo.setStyleSheet(self._input_style())
        channel_layout.addWidget(channel_label)
        channel_layout.addWidget(channel_combo)
        channel_layout.addStretch()
        settings_layout.addLayout(channel_layout)

        settings_frame.setLayout(settings_layout)
        global_layout.addWidget(settings_frame)
        global_layout.addStretch()
        global_tab.setLayout(global_layout)
        tabs.addTab(global_tab, "Global")

        # MIDI Routing tab
        routing_tab = QWidget()
        routing_layout = QVBoxLayout()
        routing_layout.setContentsMargins(20, 20, 20, 20)
        title_routing = QLabel("MIDI Routing")
        title_routing.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 14px; font-weight: bold;")
        routing_layout.addWidget(title_routing)

        routing_info = QLabel(
            "MIDI Port 1: MPC Studio 2 MIDI Port (Notes, Transport)\n"
            "MIDI Port 2: MPC Studio 2 DAW Port (CC, Control)\n"
            "MIDI Port 3: MPC Studio 2 Plugin Port (Studio Instruments)\n\n"
            "Click to configure routing..."
        )
        routing_info.setStyleSheet(f"color: {SelahOSStyle.TEXT_SECONDARY}; padding: 20px;")
        routing_layout.addWidget(routing_info)
        routing_layout.addStretch()
        routing_tab.setLayout(routing_layout)
        tabs.addTab(routing_tab, "MIDI Routing")

        return tabs

    def _setup_styles(self):
        """Apply global styles"""
        self.setStyleSheet(f"""
            QMainWindow {{
                background-color: {SelahOSStyle.PRIMARY};
                color: {SelahOSStyle.TEXT_PRIMARY};
            }}
            QLabel {{
                color: {SelahOSStyle.TEXT_PRIMARY};
            }}
            QTabWidget {{
                background-color: {SelahOSStyle.PRIMARY};
            }}
        """)

    def _button_style(self, small: bool = False) -> str:
        """Get button stylesheet"""
        height = "30px" if small else "40px"
        return f"""
            QPushButton {{
                background-color: #1a1a1a;
                color: {SelahOSStyle.ACCENT};
                border: 1px solid {SelahOSStyle.ACCENT};
                border-radius: 3px;
                font-weight: bold;
                padding: 5px;
                height: {height};
            }}
            QPushButton:hover {{
                background-color: #2a2a2a;
            }}
            QPushButton:pressed {{
                background-color: #3a3a3a;
            }}
        """

    def _input_style(self) -> str:
        """Get input widget stylesheet"""
        return f"""
            QSpinBox, QComboBox {{
                background-color: #1a1a1a;
                color: {SelahOSStyle.ACCENT};
                border: 1px solid {SelahOSStyle.ACCENT};
                border-radius: 3px;
                padding: 5px;
            }}
            QSpinBox::up-button, QSpinBox::down-button {{
                background-color: #1a1a1a;
            }}
        """

    @staticmethod
    def _find_port(names: List[str], must_contain: str, must_not_contain: Optional[str] = None) -> Optional[str]:
        for name in names:
            if must_contain in name and (must_not_contain is None or must_not_contain not in name):
                return name
        return None

    def _check_connection(self):
        """Check both the raw USB device and the selah-mpc-bridge virtual ports.

        We talk exclusively through the bridge (SelahMPC / SelahMPC Feedback)
        because it already handles the device's raw handshake/protocol — the
        editor never opens the raw "MPC Studio ..." ports directly.
        """
        try:
            out_names = mido.get_output_names()
            in_names = mido.get_input_names()

            device_seen = any('MPC' in p and 'Studio' in p for p in out_names)
            pad_in_name = self._find_port(in_names, "SelahMPC", must_not_contain="Feedback")
            led_out_name = self._find_port(out_names, "SelahMPC Feedback")
            bridge_up = bool(pad_in_name and led_out_name)

            if bridge_up and not self.bridge_status:
                self._open_bridge_ports(pad_in_name, led_out_name)
            elif not bridge_up and self.bridge_status:
                self._close_bridge_ports()

            if device_seen != self.connection_status or bridge_up != self.bridge_status:
                self.connection_status = device_seen
                self.bridge_status = bridge_up

                if device_seen and bridge_up:
                    status_text, color = "● Connected", SelahOSStyle.SUCCESS
                    bar_text = "MPC Studio 2 is ready to use — pad I/O live via selah-mpc-bridge"
                elif device_seen and not bridge_up:
                    status_text, color = "● Bridge offline", SelahOSStyle.DANGER
                    bar_text = "Device detected but selah-mpc-bridge isn't running — run: systemctl --user start selah-mpc-bridge"
                elif not device_seen and bridge_up:
                    status_text, color = "● Waiting for device", SelahOSStyle.DANGER
                    bar_text = "Bridge is running but MPC Studio 2 is not plugged in"
                else:
                    status_text, color = "● Not connected", SelahOSStyle.DANGER
                    bar_text = "Waiting for MPC Studio 2... (plug in device)"

                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")
                self.status_label.setText(bar_text)
        except Exception as e:
            self.status_label.setText(f"Error checking connection: {e}")

    def _open_bridge_ports(self, pad_in_name: str, led_out_name: str):
        try:
            self._midi_in_pads = mido.open_input(pad_in_name)
            self._midi_out_leds = mido.open_output(led_out_name)
        except Exception as e:
            self._midi_in_pads = None
            self._midi_out_leds = None
            self.status_label.setText(f"Failed to open bridge ports: {e}")

    def _close_bridge_ports(self):
        for attr in ("_midi_in_pads", "_midi_out_leds"):
            port = getattr(self, attr, None)
            if port is not None:
                try:
                    port.close()
                except Exception:
                    pass
                setattr(self, attr, None)

    def _poll_pad_input(self):
        """Non-blocking read of real pad hits arriving from the hardware."""
        if not self._midi_in_pads:
            return
        try:
            for msg in self._midi_in_pads.iter_pending():
                if msg.type not in ("note_on", "note_off"):
                    continue
                if msg.channel != PAD_MIDI_CHANNEL:
                    continue
                pad_num = NOTE_TO_PAD_NUM.get(msg.note)
                if pad_num is None:
                    continue
                is_down = msg.type == "note_on" and msg.velocity > 0
                for grid in self.pad_grids:
                    grid.flash_pad(pad_num, lit=is_down)
                label = PadGrid.PAD_LABELS.get(pad_num, f"PAD {pad_num}").replace("\n", " ")
                if is_down:
                    self.status_label.setText(f"PAD {pad_num} ({label}) hit — velocity {msg.velocity}")
        except Exception as e:
            self.status_label.setText(f"MIDI read error: {e}")

    def _on_pad_event(self, pad_num: int, is_down: bool):
        """A pad was pressed/released in the editor UI — forward to hardware LEDs."""
        note = PAD_NUM_TO_NOTE.get(pad_num)
        if note is None or not self._midi_out_leds:
            return
        try:
            msg = mido.Message(
                'note_on' if is_down else 'note_off',
                channel=FEEDBACK_MIDI_CHANNEL,
                note=note,
                velocity=100 if is_down else 0,
            )
            self._midi_out_leds.send(msg)
        except Exception as e:
            self.status_label.setText(f"MIDI send error: {e}")

    def closeEvent(self, event):
        self._close_bridge_ports()
        super().closeEvent(event)

    def _on_sync(self):
        """Sync all settings"""
        QMessageBox.information(self, "Sync", "Syncing all settings with device...")

    def _on_get_preset(self):
        """Get preset from device"""
        QMessageBox.information(self, "Get Preset", "Reading preset from device...")

    def _on_send_preset(self):
        """Send preset to device"""
        QMessageBox.information(self, "Send Preset", "Sending preset to device...")


def main():
    """Run the application"""
    app = QApplication(sys.argv)

    # Set application style
    app.setStyle('Fusion')

    # Create and show window
    window = MPCStudio2Editor()
    window.show()

    sys.exit(app.exec())


if __name__ == '__main__':
    main()
