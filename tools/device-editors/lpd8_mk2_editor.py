#!/usr/bin/env python3
"""
SelahOS LPD8 mk2 Editor
Akai Professional LPD8 mk2 (VID_09E8:PID_0001)
8-pad compact MIDI controller with 8 assignable knobs
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QGridLayout, QFrame
)
from PyQt6.QtCore import Qt, QTimer, QSize
from PyQt6.QtGui import QFont

try:
    import mido
except ImportError:
    print("ERROR: python-mido not found. Install with: pip install python-mido")
    sys.exit(1)


class SelahOSTheme:
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


class PadGrid(QWidget):
    """8-pad grid for LPD8 mk2 (1x8 layout)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(10)
        layout.setContentsMargins(20, 20, 20, 20)

        self.pads = {}

        # Create 8 pads in horizontal layout
        for pad_num in range(1, 9):
            pad = self._create_pad_button(pad_num)
            self.pads[pad_num] = pad
            layout.addWidget(pad)

        self.setLayout(layout)

    def _create_pad_button(self, pad_num: int) -> QPushButton:
        btn = QPushButton(f"Pad {pad_num}")
        btn.setFixedSize(QSize(70, 70))
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: #1a1a1a;
                color: {SelahOSTheme.ACCENT};
                border: 2px solid {SelahOSTheme.ACCENT};
                border-radius: 5px;
                font-weight: bold;
                font-size: 10px;
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


class KnobDisplay(QWidget):
    """Display for 8 assignable knobs"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        self.knobs = {}

        for knob_num in range(1, 9):
            knob_frame = QFrame()
            knob_frame.setStyleSheet(f"""
                QFrame {{
                    background-color: #1a1a1a;
                    border: 2px solid {SelahOSTheme.ACCENT};
                    border-radius: 5px;
                }}
            """)
            knob_layout = QVBoxLayout()
            knob_layout.setContentsMargins(10, 10, 10, 10)

            label = QLabel(f"Knob {knob_num}")
            label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-weight: bold;")
            label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            knob_layout.addWidget(label)

            value = QLabel("CC42")
            value.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY}; font-size: 9px;")
            value.setAlignment(Qt.AlignmentFlag.AlignCenter)
            knob_layout.addWidget(value)

            knob_frame.setLayout(knob_layout)
            layout.addWidget(knob_frame)
            self.knobs[knob_num] = {"frame": knob_frame, "value": value}

        self.setLayout(layout)


class LPD8mk2Editor(QMainWindow):
    """LPD8 mk2 Editor - SelahOS Edition"""

    DEVICE_INFO = {
        "name": "Akai Professional LPD8 mk2",
        "usb_vid": "09E8",
        "usb_pid": "0001",
        "controls": "8 pads, 8 knobs",
    }

    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"{self.DEVICE_INFO['name']} — SelahOS")
        self.setGeometry(100, 100, 1000, 600)
        self.connection_status = False

        self._setup_ui()
        self._setup_styles()

        # Status update timer
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self._check_connection)
        self.update_timer.start(1000)

    def _setup_ui(self):
        """Build UI"""
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Header
        header = self._create_header()
        main_layout.addWidget(header)

        # Pads
        pads_label = QLabel("8-Pad Grid")
        pads_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(pads_label)

        pad_grid = PadGrid()
        main_layout.addWidget(pad_grid)

        # Knobs
        knobs_label = QLabel("Assignable Knobs (8)")
        knobs_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(knobs_label)

        knobs = KnobDisplay()
        main_layout.addWidget(knobs)

        main_layout.addStretch()

        # Status bar
        self.status_label = QLabel("Waiting for LPD8 mk2...")
        self.status_label.setStyleSheet(f"""
            background-color: {SelahOSTheme.PRIMARY};
            color: {SelahOSTheme.DANGER};
            padding: 8px;
            font-weight: bold;
        """)
        main_layout.addWidget(self.status_label)

        central.setLayout(main_layout)

    def _create_header(self) -> QWidget:
        """Create header"""
        header = QWidget()
        header.setStyleSheet(f"background-color: {SelahOSTheme.PRIMARY};")
        header.setMaximumHeight(70)

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 10, 20, 10)

        # Logo
        logo = QLabel("SELAH")
        logo.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold;")
        layout.addWidget(logo)

        # Title
        title = QLabel("LPD8 mk2 Editor")
        title.setStyleSheet(f"color: {SelahOSTheme.TEXT_PRIMARY}; font-size: 18px; font-weight: bold;")
        layout.addWidget(title)

        layout.addStretch()

        # Status
        self.connection_label = QLabel("● Not connected")
        self.connection_label.setStyleSheet(f"color: {SelahOSTheme.DANGER}; font-weight: bold;")
        layout.addWidget(self.connection_label)

        header.setLayout(layout)
        return header

    def _setup_styles(self):
        """Apply styles"""
        self.setStyleSheet(f"""
            QMainWindow {{
                background-color: {SelahOSTheme.PRIMARY};
                color: {SelahOSTheme.TEXT_PRIMARY};
            }}
            QLabel {{
                color: {SelahOSTheme.TEXT_PRIMARY};
            }}
        """)

    def _check_connection(self):
        """Check device connection"""
        try:
            result = subprocess.run(
                ["lsusb"],
                capture_output=True,
                text=True,
                check=True
            )
            connected = "09e8:0001" in result.stdout.lower()

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSTheme.SUCCESS if connected else SelahOSTheme.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "LPD8 mk2 is ready to use" if connected
                    else "Waiting for LPD8 mk2... (plug in device)"
                )
        except:
            pass


def main():
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    window = LPD8mk2Editor()
    window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    import subprocess
    main()
