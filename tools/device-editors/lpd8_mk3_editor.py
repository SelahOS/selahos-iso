#!/usr/bin/env python3
"""
SelahOS LPD8 mk3 Editor
Akai Professional LPD8 mk3 (VID_09E8:PID_0004)
8 RGB pads with 8 assignable knobs
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QGridLayout, QFrame, QComboBox
)
from PyQt6.QtCore import Qt, QTimer, QSize
from PyQt6.QtGui import QFont, QColor

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


class RGBPadGrid(QWidget):
    """8 RGB pads with color control"""

    RGB_COLORS = [
        ("Red", "#ff0000"),
        ("Green", "#00ff00"),
        ("Blue", "#0000ff"),
        ("Yellow", "#ffff00"),
        ("Cyan", "#00ffff"),
        ("Magenta", "#ff00ff"),
        ("Orange", "#ff8800"),
        ("White", "#ffffff"),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(12)
        layout.setContentsMargins(20, 20, 20, 20)

        self.pads = {}

        for pad_num in range(1, 9):
            pad_frame = QFrame()
            pad_frame.setStyleSheet(f"""
                QFrame {{
                    background-color: #1a1a1a;
                    border: 2px solid {SelahOSTheme.ACCENT};
                    border-radius: 5px;
                }}
            """)
            pad_layout = QVBoxLayout()
            pad_layout.setContentsMargins(10, 10, 10, 10)

            # Pad button
            pad_btn = QPushButton(f"Pad {pad_num}")
            pad_btn.setFixedSize(QSize(60, 60))
            pad_btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: #ff0000;
                    border-radius: 5px;
                    font-weight: bold;
                }}
                QPushButton:hover {{
                    background-color: #ff4444;
                }}
            """)
            pad_layout.addWidget(pad_btn)

            # Color selector
            color_combo = QComboBox()
            color_combo.addItems([color[0] for color in self.RGB_COLORS])
            color_combo.setStyleSheet(f"""
                QComboBox {{
                    background-color: #1a1a1a;
                    color: {SelahOSTheme.ACCENT};
                    border: 1px solid {SelahOSTheme.ACCENT};
                    border-radius: 3px;
                    padding: 3px;
                    font-size: 9px;
                }}
            """)
            pad_layout.addWidget(color_combo)

            pad_frame.setLayout(pad_layout)
            layout.addWidget(pad_frame)
            self.pads[pad_num] = {"button": pad_btn, "color_combo": color_combo}

        self.setLayout(layout)


class KnobDisplay(QWidget):
    """8 assignable knobs"""

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
            label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-weight: bold; font-size: 9px;")
            label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            knob_layout.addWidget(label)

            value = QLabel("CC42")
            value.setStyleSheet(f"color: {SelahOSTheme.TEXT_SECONDARY}; font-size: 8px;")
            value.setAlignment(Qt.AlignmentFlag.AlignCenter)
            knob_layout.addWidget(value)

            knob_frame.setLayout(knob_layout)
            layout.addWidget(knob_frame)
            self.knobs[knob_num] = {"frame": knob_frame, "value": value}

        self.setLayout(layout)


class LPD8mk3Editor(QMainWindow):
    """LPD8 mk3 Editor with RGB support"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("LPD8 mk3 — SelahOS")
        self.setGeometry(100, 100, 1100, 500)
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

        # RGB Pads
        pads_label = QLabel("8 RGB Pads")
        pads_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(pads_label)

        pads = RGBPadGrid()
        main_layout.addWidget(pads)

        # Knobs
        knobs_label = QLabel("Assignable Knobs (8)")
        knobs_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 14px; font-weight: bold; padding: 10px 20px;")
        main_layout.addWidget(knobs_label)

        knobs = KnobDisplay()
        main_layout.addWidget(knobs)

        main_layout.addStretch()

        # Status
        self.status_label = QLabel("Waiting for LPD8 mk3...")
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

        title = QLabel("LPD8 mk3 Editor")
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
            connected = "09e8:0004" in result.stdout.lower()

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSTheme.SUCCESS if connected else SelahOSTheme.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "LPD8 mk3 is ready to use" if connected
                    else "Waiting for LPD8 mk3... (plug in device)"
                )
        except:
            pass


def main():
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    window = LPD8mk3Editor()
    window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
