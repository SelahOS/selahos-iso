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
    """Visual representation of MPC Studio 2 pads (4x4 grid)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSStyle.SECONDARY};")

        layout = QGridLayout()
        layout.setSpacing(8)
        layout.setContentsMargins(20, 20, 20, 20)

        self.pads = {}

        # Create 4x4 grid of pads
        for row in range(4):
            for col in range(4):
                pad_num = row * 4 + col + 1
                pad = self._create_pad_button(pad_num)
                self.pads[pad_num] = pad
                layout.addWidget(pad, row, col)

        self.setLayout(layout)

    def _create_pad_button(self, pad_num: int) -> QPushButton:
        """Create a single pad button"""
        btn = QPushButton(f"Pad {pad_num}")
        btn.setFixedSize(QSize(80, 80))

        # Style the pad
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: #1a1a1a;
                color: {SelahOSStyle.ACCENT};
                border: 2px solid {SelahOSStyle.ACCENT};
                border-radius: 5px;
                font-weight: bold;
                font-size: 11px;
            }}
            QPushButton:hover {{
                background-color: #2a2a2a;
                border: 2px solid #ffff00;
            }}
            QPushButton:pressed {{
                background-color: #3a3a3a;
            }}
        """)

        return btn


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
        self.setGeometry(100, 100, 1400, 900)

        # Try to load device profile
        self.device_profile = self._load_device_profile()
        self.midi_device = None
        self.connection_status = False

        # Setup UI
        self._setup_ui()
        self._setup_styles()

        # Connection timer
        self.check_timer = QTimer()
        self.check_timer.timeout.connect(self._check_connection)
        self.check_timer.start(1000)  # Check every second

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
        controller_layout = QVBoxLayout()
        controller_layout.setContentsMargins(20, 20, 20, 20)

        # Title
        title = QLabel("MPC Studio 2 — Live Controller View")
        title.setStyleSheet(f"color: {SelahOSStyle.ACCENT}; font-size: 16px; font-weight: bold;")
        controller_layout.addWidget(title)

        # Pad grid
        pad_grid = PadGrid()
        controller_layout.addWidget(pad_grid)

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
        pads_layout.addWidget(PadGrid())
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

    def _check_connection(self):
        """Check if device is connected"""
        try:
            ports = mido.get_output_names()
            connected = any('MPC' in p and 'Studio' in p for p in ports)

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSStyle.SUCCESS if connected else SelahOSStyle.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "MPC Studio 2 is ready to use" if connected
                    else "Waiting for MPC Studio 2... (plug in device)"
                )
        except Exception as e:
            self.status_label.setText(f"Error checking connection: {e}")

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
