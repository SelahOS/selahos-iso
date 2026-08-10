#!/usr/bin/env python3
"""
SelahOS MPD226 Editor
Akai Professional MPD226 (VID_09E8:PID_0003)
16-pad controller with 8 faders
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QGridLayout, QFrame, QSlider
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


class PadGrid16(QWidget):
    """16-pad grid (4x4)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QGridLayout()
        layout.setSpacing(8)
        layout.setContentsMargins(20, 20, 20, 20)

        self.pads = {}

        for row in range(4):
            for col in range(4):
                pad_num = row * 4 + col + 1
                pad = QPushButton(f"Pad {pad_num}")
                pad.setFixedSize(QSize(80, 80))
                pad.setStyleSheet(f"""
                    QPushButton {{
                        background-color: #1a1a1a;
                        color: {SelahOSTheme.ACCENT};
                        border: 2px solid {SelahOSTheme.ACCENT};
                        border-radius: 5px;
                        font-weight: bold;
                    }}
                    QPushButton:hover {{
                        background-color: #2a2a2a;
                        border: 2px solid #ffff00;
                    }}
                """)
                layout.addWidget(pad, row, col)
                self.pads[pad_num] = pad

        self.setLayout(layout)


class FaderDisplay(QWidget):
    """8 faders display"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        self.faders = {}

        for fader_num in range(1, 9):
            fader_frame = QFrame()
            fader_frame.setStyleSheet(f"""
                QFrame {{
                    background-color: #1a1a1a;
                    border: 2px solid {SelahOSTheme.ACCENT};
                    border-radius: 5px;
                }}
            """)
            fader_layout = QVBoxLayout()
            fader_layout.setContentsMargins(5, 10, 5, 10)

            label = QLabel(f"Fader {fader_num}")
            label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-weight: bold; font-size: 10px;")
            label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            fader_layout.addWidget(label)

            slider = QSlider(Qt.Orientation.Vertical)
            slider.setMinimum(0)
            slider.setMaximum(127)
            slider.setValue(64)
            slider.setStyleSheet(f"""
                QSlider::groove:vertical {{
                    background-color: #1a1a1a;
                    width: 8px;
                    border: 1px solid {SelahOSTheme.ACCENT};
                    border-radius: 4px;
                }}
                QSlider::handle:vertical {{
                    background-color: {SelahOSTheme.ACCENT};
                    height: 20px;
                    margin: 0 -5px;
                    border-radius: 5px;
                }}
            """)
            fader_layout.addWidget(slider)

            value_label = QLabel("64")
            value_label.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY}; font-size: 9px;")
            value_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            fader_layout.addWidget(value_label)

            slider.valueChanged.connect(lambda val, lbl=value_label: lbl.setText(str(val)))

            fader_frame.setLayout(fader_layout)
            layout.addWidget(fader_frame)
            self.faders[fader_num] = {"frame": fader_frame, "slider": slider}

        self.setLayout(layout)


class MPD226Editor(QMainWindow):
    """MPD226 Editor"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("MPD226 — SelahOS")
        self.setGeometry(100, 100, 1200, 700)
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

        # Header
        header = self._create_header()
        main_layout.addWidget(header)

        # Pads
        pads_label = QLabel("16-Pad Grid")
        pads_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(pads_label)

        pads = PadGrid16()
        main_layout.addWidget(pads)

        # Faders
        faders_label = QLabel("8 Faders")
        faders_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(faders_label)

        faders = FaderDisplay()
        main_layout.addWidget(faders)

        main_layout.addStretch()

        # Status
        self.status_label = QLabel("Waiting for MPD226...")
        self.status_label.setStyleSheet(f"""
            background-color: {SelahOSTheme.PRIMARY};
            color: {SelahOSTheme.DANGER};
            padding: 8px;
            font-weight: bold;
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

        title = QLabel("MPD226 Editor")
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
            connected = "09e8:0003" in result.stdout.lower()

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSTheme.SUCCESS if connected else SelahOSTheme.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "MPD226 is ready to use" if connected
                    else "Waiting for MPD226... (plug in device)"
                )
        except:
            pass


def main():
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    window = MPD226Editor()
    window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
