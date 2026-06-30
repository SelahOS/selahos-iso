#!/usr/bin/env python3
"""
SelahOS APC mini Editor
Akai Professional APC mini (VID_09E8:PID_0005)
64-pad grid (8x8) controller
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QGridLayout, QFrame, QScrollArea
)
from PyQt6.QtCore import Qt, QTimer, QSize
from PyQt6.QtGui import QFont

try:
    import mido
except ImportError:
    print("ERROR: python-mido not found")
    sys.exit(1)


class SelahOSTheme:
    PRIMARY = "#1e1e1e"
    SECONDARY = "#2a2a2a"
    ACCENT = "#D4AF37"
    SUCCESS = "#44ff44"
    DANGER = "#ff4444"
    TEXT_PRIMARY = "#ffffff"
    TEXT_SECONDARY = "#888888"


class PadGrid64(QWidget):
    """64-pad grid (8x8) for APC mini"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QGridLayout()
        layout.setSpacing(4)
        layout.setContentsMargins(15, 15, 15, 15)

        self.pads = {}

        for row in range(8):
            for col in range(8):
                pad_num = row * 8 + col + 1
                pad = QPushButton("")
                pad.setFixedSize(QSize(50, 50))
                pad.setStyleSheet(f"""
                    QPushButton {{
                        background-color: #1a1a1a;
                        border: 1px solid {SelahOSTheme.ACCENT};
                        border-radius: 3px;
                    }}
                    QPushButton:hover {{
                        background-color: #2a2a2a;
                        border: 1px solid #ffff00;
                    }}
                """)
                pad.setToolTip(f"Pad {pad_num}")
                layout.addWidget(pad, row, col)
                self.pads[pad_num] = pad

        self.setLayout(layout)


class ControlPanel(QWidget):
    """Transport and control buttons"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(10)
        layout.setContentsMargins(15, 10, 15, 10)

        controls = ["Shift", "Master", "Clip", "Device", "User", "Undo", "Metronome", "Tap Tempo"]

        for ctrl_name in controls:
            btn = QPushButton(ctrl_name)
            btn.setFixedSize(QSize(100, 40))
            btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: #1a1a1a;
                    color: {SelahOSTheme.ACCENT};
                    border: 1px solid {SelahOSTheme.ACCENT};
                    border-radius: 3px;
                    font-size: 9px;
                    font-weight: bold;
                }}
                QPushButton:hover {{
                    background-color: #2a2a2a;
                }}
                QPushButton:pressed {{
                    background-color: #3a3a3a;
                }}
            """)
            layout.addWidget(btn)

        layout.addStretch()
        self.setLayout(layout)


class APCminiEditor(QMainWindow):
    """APC mini Editor"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("APC mini — SelahOS")
        self.setGeometry(50, 50, 800, 900)
        self.connection_status = False

        self._setup_ui()
        self._setup_styles()

        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self._check_connection)
        self.update_timer.start(1000)

    def _setup_ui(self):
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Header
        header = self._create_header()
        main_layout.addWidget(header)

        # Control panel
        controls = ControlPanel()
        main_layout.addWidget(controls)

        # Pads section
        pads_label = QLabel("64-Pad Grid (8×8)")
        pads_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 13px; font-weight: bold; padding: 10px 15px;")
        main_layout.addWidget(pads_label)

        # Scrollable pad grid
        scroll = QScrollArea()
        scroll.setWidgetResizable(False)
        scroll.setStyleSheet(f"""
            QScrollArea {{
                background-color: {SelahOSTheme.SECONDARY};
                border: none;
            }}
        """)
        pads = PadGrid64()
        scroll.setWidget(pads)
        main_layout.addWidget(scroll)

        # Status
        self.status_label = QLabel("Waiting for APC mini...")
        self.status_label.setStyleSheet(f"""
            background-color: {SelahOSTheme.PRIMARY};
            color: {SelahOSTheme.DANGER};
            padding: 8px;
            font-weight: bold;
            font-size: 11px;
        """)
        main_layout.addWidget(self.status_label)

        central.setLayout(main_layout)

    def _create_header(self) -> QWidget:
        header = QWidget()
        header.setStyleSheet(f"background-color: {SelahOSTheme.PRIMARY};")
        header.setMaximumHeight(70)

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 10, 20, 10)

        logo = QLabel("SELAH")
        logo.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold;")
        layout.addWidget(logo)

        title = QLabel("APC mini Editor")
        title.setStyleSheet(f"color: {SelahOSTheme.TEXT_PRIMARY}; font-size: 18px; font-weight: bold;")
        layout.addWidget(title)

        layout.addStretch()

        self.connection_label = QLabel("● Not connected")
        self.connection_label.setStyleSheet(f"color: {SelahOSTheme.DANGER}; font-weight: bold;")
        layout.addWidget(self.connection_label)

        header.setLayout(layout)
        return header

    def _setup_styles(self):
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
        try:
            import subprocess
            result = subprocess.run(
                ["lsusb"],
                capture_output=True,
                text=True,
                check=True
            )
            connected = "09e8:0005" in result.stdout.lower()

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSTheme.SUCCESS if connected else SelahOSTheme.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "APC mini is ready to use" if connected
                    else "Waiting for APC mini... (plug in device)"
                )
        except:
            pass


def main():
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    window = APCminiEditor()
    window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
