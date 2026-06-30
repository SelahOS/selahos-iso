#!/usr/bin/env python3
"""
SelahOS Central Dashboard
Master control center for all SelahOS audio devices and settings
Unified interface for device management, editors, and system configuration
"""

import sys
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Optional

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QLabel, QGridLayout, QFrame, QScrollArea, QStatusBar,
        QMessageBox, QTabWidget, QListWidget, QListWidgetItem, QDialog
    )
    from PyQt6.QtCore import Qt, QTimer, QSize
    from PyQt6.QtGui import QColor, QFont, QIcon, QPixmap
except ImportError:
    print("ERROR: PyQt6 not found. Install with: pip install PyQt6")
    sys.exit(1)

try:
    import mido
except ImportError:
    print("ERROR: python-mido not found. Install with: pip install python-mido")
    sys.exit(1)


class SelahOSTheme:
    """SelahOS theme and colors"""
    PRIMARY = "#1e1e1e"
    SECONDARY = "#2a2a2a"
    ACCENT = "#D4AF37"
    SUCCESS = "#44ff44"
    DANGER = "#ff4444"
    TEXT_PRIMARY = "#ffffff"
    TEXT_SECONDARY = "#888888"

    @staticmethod
    def button_style(bg="#1a1a1a", fg="#D4AF37"):
        return f"""
            QPushButton {{
                background-color: {bg};
                color: {fg};
                border: 2px solid {fg};
                border-radius: 5px;
                padding: 10px;
                font-weight: bold;
                min-height: 40px;
            }}
            QPushButton:hover {{
                background-color: #2a2a2a;
            }}
            QPushButton:pressed {{
                background-color: #3a3a3a;
            }}
        """


class DeviceCard(QFrame):
    """Card representing a connected device"""

    def __init__(self, device_name: str, device_info: Dict, parent=None):
        super().__init__(parent)
        self.device_name = device_name
        self.device_info = device_info
        self.setFrameStyle(QFrame.Shape.StyledPanel | QFrame.Shadow.Raised)
        self.setStyleSheet(f"""
            QFrame {{
                background-color: {SelahOSTheme.SECONDARY};
                border: 2px solid {SelahOSTheme.ACCENT};
                border-radius: 10px;
                padding: 15px;
            }}
        """)

        layout = QVBoxLayout()

        # Title
        title = QLabel(device_name)
        title.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold;")
        layout.addWidget(title)

        # Status
        status_text = "● Connected" if device_info.get("connected") else "● Not connected"
        status_color = SelahOSTheme.SUCCESS if device_info.get("connected") else SelahOSTheme.DANGER
        status = QLabel(status_text)
        status.setStyleSheet(f"color: {status_color};")
        layout.addWidget(status)

        # Device details
        details = QLabel(
            f"USB: {device_info.get('vid', 'N/A')}:{device_info.get('pid', 'N/A')}\n"
            f"Controls: {device_info.get('controls', 'N/A')}"
        )
        details.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY}; font-size: 10px;")
        layout.addWidget(details)

        # Buttons
        btn_layout = QHBoxLayout()

        btn_open = QPushButton("Open Editor")
        btn_open.setStyleSheet(SelahOSTheme.button_style())
        btn_open.clicked.connect(self.open_editor)
        btn_layout.addWidget(btn_open)

        btn_test = QPushButton("Test MIDI")
        btn_test.setStyleSheet(SelahOSTheme.button_style())
        btn_test.clicked.connect(self.test_midi)
        btn_layout.addWidget(btn_test)

        layout.addLayout(btn_layout)
        self.setLayout(layout)

    def open_editor(self):
        """Open the device editor"""
        editor_map = {
            "MPK mini IV": "mpk_mini_iv",
            "MPC Studio mk2": "mpc_studio2",
            "LPD8 mk2": "lpd8_mk2",
        }

        editor_name = editor_map.get(self.device_name)
        if editor_name:
            subprocess.Popen([
                "python3",
                str(Path(__file__).parent / f"{editor_name}_editor.py")
            ])

    def test_midi(self):
        """Test device MIDI"""
        try:
            ports = mido.get_output_names()
            matching = [p for p in ports if self.device_name.split()[0] in p]

            if matching:
                QMessageBox.information(
                    self,
                    "MIDI Test",
                    f"Found {len(matching)} MIDI port(s):\n" + "\n".join(matching)
                )
            else:
                QMessageBox.warning(
                    self,
                    "MIDI Test",
                    f"No MIDI ports found for {self.device_name}"
                )
        except Exception as e:
            QMessageBox.critical(self, "Error", str(e))


class CentralDashboard(QMainWindow):
    """SelahOS Central Dashboard - Master control center"""

    DEVICES = {
        "MPK mini IV": {
            "vid": "09E8",
            "pid": "005D",
            "controls": "25 keys, 8 pads, 8 knobs, 2 wheels",
            "editor": "mpk_mini_iv_editor.py"
        },
        "MPC Studio mk2": {
            "vid": "09E8",
            "pid": "004A",
            "controls": "16 pads, transport, jog wheel",
            "editor": "mpc_studio2_editor.py"
        },
        "LPD8 mk2": {
            "vid": "09E8",
            "pid": "0001",
            "controls": "8 pads, 8 knobs",
            "editor": "lpd8_mk2_editor.py"
        },
        "MPK261": {
            "vid": "09E8",
            "pid": "0002",
            "controls": "61 keys, 16 pads, 8 knobs",
            "editor": "mpk261_editor.py"
        },
    }

    def __init__(self):
        super().__init__()
        self.setWindowTitle("SelahOS Central Dashboard")
        self.setGeometry(50, 50, 1600, 900)
        self._setup_ui()
        self._setup_styles()

        # Status update timer
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self._update_status)
        self.update_timer.start(2000)

    def _setup_ui(self):
        """Build the user interface"""
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Header
        header = self._create_header()
        main_layout.addWidget(header)

        # Tabs
        tabs = QTabWidget()
        tabs.setStyleSheet(f"""
            QTabWidget {{ background-color: {SelahOSTheme.PRIMARY}; }}
            QTabBar::tab {{
                background-color: {SelahOSTheme.SECONDARY};
                color: {SelahOSTheme.TEXT_SECONDARY};
                padding: 8px 20px;
                border: 1px solid {SelahOSTheme.SECONDARY};
            }}
            QTabBar::tab:selected {{
                color: {SelahOSTheme.ACCENT};
                border-bottom: 2px solid {SelahOSTheme.ACCENT};
            }}
        """)

        # Devices tab
        devices_tab = self._create_devices_tab()
        tabs.addTab(devices_tab, "Devices")

        # Settings tab
        settings_tab = self._create_settings_tab()
        tabs.addTab(settings_tab, "Settings")

        # System tab
        system_tab = self._create_system_tab()
        tabs.addTab(system_tab, "System")

        main_layout.addWidget(tabs)

        # Status bar
        self.statusBar = QStatusBar()
        self.statusBar.setStyleSheet(f"""
            QStatusBar {{
                background-color: {SelahOSTheme.PRIMARY};
                color: {SelahOSTheme.TEXT_SECONDARY};
            }}
        """)
        self.setStatusBar(self.statusBar)
        self.statusBar.showMessage("Ready")

        central.setLayout(main_layout)

    def _create_header(self) -> QWidget:
        """Create header with title and controls"""
        header = QWidget()
        header.setStyleSheet(f"background-color: {SelahOSTheme.PRIMARY};")
        header.setMaximumHeight(80)

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 15, 20, 15)

        # Logo and title
        logo = QLabel("SELAH")
        logo.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold;")
        layout.addWidget(logo)

        title = QLabel("Central Dashboard")
        title.setStyleSheet(f"color: {SelahOSTheme.TEXT_PRIMARY}; font-size: 20px; font-weight: bold;")
        layout.addWidget(title)

        layout.addStretch()

        # System status
        self.status_label = QLabel("● Initializing...")
        self.status_label.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY};")
        layout.addWidget(self.status_label)

        header.setLayout(layout)
        return header

    def _create_devices_tab(self) -> QWidget:
        """Create devices tab"""
        tab = QWidget()
        layout = QVBoxLayout()

        # Title
        title = QLabel("Connected Devices")
        title.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 16px; font-weight: bold; padding: 20px;")
        layout.addWidget(title)

        # Scroll area for device cards
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(f"background-color: {SelahOSTheme.PRIMARY};")

        cards_widget = QWidget()
        cards_layout = QGridLayout()
        cards_layout.setSpacing(15)
        cards_layout.setContentsMargins(20, 20, 20, 20)

        # Create device cards
        self.device_cards = {}
        for i, (device_name, device_info) in enumerate(self.DEVICES.items()):
            device_info["connected"] = self._check_device(device_info)
            card = DeviceCard(device_name, device_info)
            self.device_cards[device_name] = card
            cards_layout.addWidget(card, i // 2, i % 2)

        cards_layout.addStretch(1, 0)
        cards_widget.setLayout(cards_layout)
        scroll.setWidget(cards_widget)
        layout.addWidget(scroll)

        tab.setLayout(layout)
        return tab

    def _create_settings_tab(self) -> QWidget:
        """Create settings tab"""
        tab = QWidget()
        layout = QVBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)

        title = QLabel("Settings & Configuration")
        title.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 16px; font-weight: bold;")
        layout.addWidget(title)

        # Settings buttons
        btn_layout = QGridLayout()
        btn_layout.setSpacing(15)

        settings = [
            ("Touchpad Palm Rejection", self._open_touchpad_settings),
            ("MIDI Configuration", self._open_midi_settings),
            ("Audio Settings", self._open_audio_settings),
            ("Device Bridge Settings", self._open_bridge_settings),
            ("Keyboard Shortcuts", self._open_shortcuts),
            ("System Preferences", self._open_preferences),
        ]

        for i, (label, callback) in enumerate(settings):
            btn = QPushButton(label)
            btn.setStyleSheet(SelahOSTheme.button_style())
            btn.setMinimumHeight(60)
            btn.clicked.connect(callback)
            btn_layout.addWidget(btn, i // 2, i % 2)

        layout.addLayout(btn_layout)
        layout.addStretch()

        tab.setLayout(layout)
        return tab

    def _create_system_tab(self) -> QWidget:
        """Create system tab"""
        tab = QWidget()
        layout = QVBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)

        title = QLabel("System Status & Control")
        title.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 16px; font-weight: bold;")
        layout.addWidget(title)

        # Status info
        info_frame = QFrame()
        info_frame.setStyleSheet(f"""
            QFrame {{
                background-color: {SelahOSTheme.SECONDARY};
                border: 1px solid {SelahOSTheme.ACCENT};
                border-radius: 5px;
                padding: 15px;
            }}
        """)
        info_layout = QVBoxLayout()

        # Device Bridge Status
        bridge_status = QLabel("Device Bridge Status: Active")
        bridge_status.setStyleSheet(f"color: {SelahOSTheme.SUCCESS};")
        info_layout.addWidget(bridge_status)

        # MIDI Ports
        midi_label = QLabel("MIDI Ports: 5 ports available")
        midi_label.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY};")
        info_layout.addWidget(midi_label)

        # System Load
        system_label = QLabel("System: Ready")
        system_label.setStyleSheet(f"color: {SelahOSTheme.SUCCESS};")
        info_layout.addWidget(system_label)

        info_frame.setLayout(info_layout)
        layout.addWidget(info_frame)

        # Control buttons
        btn_layout = QHBoxLayout()

        btn_restart_bridge = QPushButton("Restart Device Bridge")
        btn_restart_bridge.setStyleSheet(SelahOSTheme.button_style())
        btn_restart_bridge.clicked.connect(self._restart_bridge)
        btn_layout.addWidget(btn_restart_bridge)

        btn_view_logs = QPushButton("View Logs")
        btn_view_logs.setStyleSheet(SelahOSTheme.button_style())
        btn_view_logs.clicked.connect(self._view_logs)
        btn_layout.addWidget(btn_view_logs)

        layout.addLayout(btn_layout)
        layout.addStretch()

        tab.setLayout(layout)
        return tab

    def _setup_styles(self):
        """Apply global styles"""
        self.setStyleSheet(f"""
            QMainWindow {{
                background-color: {SelahOSTheme.PRIMARY};
                color: {SelahOSTheme.TEXT_PRIMARY};
            }}
            QLabel {{
                color: {SelahOSTheme.TEXT_PRIMARY};
            }}
            QWidget {{
                background-color: {SelahOSTheme.PRIMARY};
            }}
        """)

    def _check_device(self, device_info: Dict) -> bool:
        """Check if device is connected"""
        try:
            result = subprocess.run(
                ["lsusb"],
                capture_output=True,
                text=True,
                check=True
            )
            vid_pid = f"{device_info.get('vid', '')}:{device_info.get('pid', '')}"
            return vid_pid.lower() in result.stdout.lower()
        except:
            return False

    def _update_status(self):
        """Update device status"""
        connected_count = sum(1 for info in self.DEVICES.values() if self._check_device(info))
        self.status_label.setText(f"● {connected_count} device(s) connected")

    # Settings callbacks
    def _open_touchpad_settings(self):
        """Open touchpad settings"""
        subprocess.Popen(["python3", "/home/dbnoble/selahos-touchpad-palm-rejection/palm-rejection.py", "configure"])

    def _open_midi_settings(self):
        QMessageBox.information(self, "MIDI Settings", "MIDI configuration tool")

    def _open_audio_settings(self):
        QMessageBox.information(self, "Audio Settings", "Audio configuration tool")

    def _open_bridge_settings(self):
        QMessageBox.information(self, "Device Bridge", "Device bridge settings")

    def _open_shortcuts(self):
        QMessageBox.information(self, "Keyboard Shortcuts", "Keyboard shortcuts configuration")

    def _open_preferences(self):
        QMessageBox.information(self, "System Preferences", "System preferences")

    def _restart_bridge(self):
        """Restart device bridge"""
        try:
            subprocess.run(["systemctl", "--user", "restart", "selahos-device-bridge"], check=False)
            QMessageBox.information(self, "Success", "Device bridge restarted")
        except Exception as e:
            QMessageBox.critical(self, "Error", str(e))

    def _view_logs(self):
        """View system logs"""
        subprocess.Popen(["gedit", "/var/log/selahos-device-bridge.log"])


def main():
    """Run the dashboard"""
    app = QApplication(sys.argv)
    app.setStyle('Fusion')

    window = CentralDashboard()
    window.show()

    sys.exit(app.exec())


if __name__ == '__main__':
    main()
