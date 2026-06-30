#!/usr/bin/env python3
"""
SelahOS MPK mini IV Editor
Akai Professional MPK mini IV (VID_09E8:PID_005D)
25 keys, 8 pads, 8 knobs, 2 wheels
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


class KeyboardDisplay(QWidget):
    """Mini keyboard visualization (25 keys)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")
        self.setMaximumHeight(80)

        layout = QHBoxLayout()
        layout.setContentsMargins(20, 10, 20, 10)
        layout.setSpacing(1)

        # Simplified 25-key visualization
        for key in range(25):
            key_type = self._get_key_type(key)
            key_btn = QPushButton("")
            key_btn.setMaximumWidth(12)
            key_btn.setMaximumHeight(70)

            if key_type == "white":
                key_btn.setStyleSheet("background-color: white; border: 1px solid black;")
            else:  # black
                key_btn.setStyleSheet("background-color: black;")

            layout.addWidget(key_btn)

        self.setLayout(layout)

    def _get_key_type(self, key: int) -> str:
        pattern = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
        return "white" if pattern[key % 12] == 0 else "black"


class PadGrid8(QWidget):
    """8-pad grid (2x4)"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QGridLayout()
        layout.setSpacing(8)
        layout.setContentsMargins(20, 20, 20, 20)

        self.pads = {}

        for row in range(2):
            for col in range(4):
                pad_num = row * 4 + col + 1
                pad = QPushButton(f"P{pad_num}")
                pad.setFixedSize(QSize(70, 70))
                pad.setStyleSheet(f"""
                    QPushButton {{
                        background-color: #1a1a1a;
                        color: {SelahOSTheme.ACCENT};
                        border: 2px solid {SelahOSTheme.ACCENT};
                        border-radius: 5px;
                        font-weight: bold;
                        font-size: 9px;
                    }}
                    QPushButton:hover {{
                        background-color: #2a2a2a;
                        border: 2px solid #ffff00;
                    }}
                """)
                layout.addWidget(pad, row, col)
                self.pads[pad_num] = pad

        self.setLayout(layout)


class KnobWheelDisplay(QWidget):
    """8 knobs + 2 wheels display"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background-color: {SelahOSTheme.SECONDARY};")

        layout = QHBoxLayout()
        layout.setSpacing(10)
        layout.setContentsMargins(20, 15, 20, 15)

        # Knobs
        knobs_frame = QFrame()
        knobs_frame.setStyleSheet(f"""
            QFrame {{
                background-color: #1a1a1a;
                border: 2px solid {SelahOSTheme.ACCENT};
                border-radius: 5px;
            }}
        """)
        knobs_layout = QHBoxLayout()
        knobs_layout.setSpacing(8)
        knobs_layout.setContentsMargins(10, 10, 10, 10)

        for knob_num in range(1, 9):
            knob = QPushButton(f"K{knob_num}")
            knob.setFixedSize(QSize(50, 50))
            knob.setStyleSheet(f"""
                QPushButton {{
                    background-color: #2a2a2a;
                    color: {SelahOSTheme.ACCENT};
                    border: 1px solid {SelahOSTheme.ACCENT};
                    border-radius: 25px;
                    font-weight: bold;
                    font-size: 8px;
                }}
            """)
            knobs_layout.addWidget(knob)

        knobs_frame.setLayout(knobs_layout)
        layout.addWidget(knobs_frame)

        # Wheels
        wheels_frame = QFrame()
        wheels_frame.setStyleSheet(f"""
            QFrame {{
                background-color: #1a1a1a;
                border: 2px solid {SelahOSTheme.ACCENT};
                border-radius: 5px;
            }}
        """)
        wheels_layout = QHBoxLayout()
        wheels_layout.setSpacing(15)
        wheels_layout.setContentsMargins(10, 10, 10, 10)

        for wheel_num, wheel_name in enumerate(["Pitch", "Mod"], 1):
            wheel_btn = QPushButton(wheel_name)
            wheel_btn.setFixedSize(QSize(80, 50))
            wheel_btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: #2a2a2a;
                    color: {SelahOSTheme.ACCENT};
                    border: 1px solid {SelahOSTheme.ACCENT};
                    border-radius: 3px;
                    font-weight: bold;
                    font-size: 9px;
                }}
            """)
            wheels_layout.addWidget(wheel_btn)

        wheels_frame.setLayout(wheels_layout)
        layout.addWidget(wheels_frame)

        self.setLayout(layout)


class MPKminiIVEditor(QMainWindow):
    """MPK mini IV Editor"""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("MPK mini IV — SelahOS")
        self.setGeometry(100, 100, 1000, 700)
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

        # Keyboard
        kb_label = QLabel("25-Key Keyboard")
        kb_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 12px; font-weight: bold; padding: 8px 20px;")
        main_layout.addWidget(kb_label)

        keyboard = KeyboardDisplay()
        main_layout.addWidget(keyboard)

        # Pads
        pads_label = QLabel("8 Pads (2×4)")
        pads_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 12px; font-weight: bold; padding: 8px 20px;")
        main_layout.addWidget(pads_label)

        pads = PadGrid8()
        main_layout.addWidget(pads)

        # Knobs & Wheels
        controls_label = QLabel("8 Knobs + 2 Wheels")
        controls_label.setStyleSheet(f"color: {SelahOSTheme.ACCENT}; font-size: 12px; font-weight: bold; padding: 8px 20px;")
        main_layout.addWidget(controls_label)

        controls = KnobWheelDisplay()
        main_layout.addWidget(controls)

        main_layout.addStretch()

        # Status
        self.status_label = QLabel("Waiting for MPK mini IV...")
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

        title = QLabel("MPK mini IV Editor")
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
            connected = "09e8:005d" in result.stdout.lower()

            if connected != self.connection_status:
                self.connection_status = connected
                status_text = "● Connected" if connected else "● Not connected"
                color = SelahOSTheme.SUCCESS if connected else SelahOSTheme.DANGER
                self.connection_label.setText(status_text)
                self.connection_label.setStyleSheet(f"color: {color}; font-weight: bold;")

                self.status_label.setText(
                    "MPK mini IV is ready to use" if connected
                    else "Waiting for MPK mini IV... (plug in device)"
                )
        except:
            pass


def main():
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    window = MPKminiIVEditor()
    window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
