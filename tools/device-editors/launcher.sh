#!/bin/bash
#
# SelahOS Device Editors Launcher
# Launches the appropriate device editor
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDITOR_DIR="$SCRIPT_DIR"

# Check if PyQt6 is installed
if ! python3 -c "import PyQt6" 2>/dev/null; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  PyQt6 is required for the SelahOS Device Editors             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Install with:"
    echo "  pip install --break-system-packages PyQt6"
    echo ""
    echo "Or via pacman (if available):"
    echo "  sudo pacman -S python-pyqt6"
    exit 1
fi

# Parse arguments
case "${1:-menu}" in
    mpk|mpk_mini_iv)
        echo "Launching MPK mini IV Editor..."
        python3 "$EDITOR_DIR/mpk_mini_iv_editor.py"
        ;;

    mpc|mpc_studio2)
        echo "Launching MPC Studio 2 Editor..."
        python3 "$EDITOR_DIR/mpc_studio2_editor.py"
        ;;

    lpd8|lpd8_mk2)
        echo "Launching LPD8 mk2 Editor..."
        python3 "$EDITOR_DIR/lpd8_mk2_editor.py"
        ;;

    mpk261)
        echo "Launching MPK261 Editor..."
        python3 "$EDITOR_DIR/mpk261_editor.py"
        ;;

    lpd8_mk3)
        echo "Launching LPD8 mk3 Editor..."
        python3 "$EDITOR_DIR/lpd8_mk3_editor.py"
        ;;

    mpd226)
        echo "Launching MPD226 Editor..."
        python3 "$EDITOR_DIR/mpd226_editor.py"
        ;;

    apc|apc_mini)
        echo "Launching APC mini Editor..."
        python3 "$EDITOR_DIR/apc_mini_editor.py"
        ;;

    menu|*)
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║           SelahOS Device Editors - Choose Device               ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Usage: selahos-device-editors [DEVICE]"
        echo ""
        echo "Devices:"
        echo "  mpk, mpk_mini_iv          - MPK mini IV Editor"
        echo "  mpc, mpc_studio2          - MPC Studio 2 Editor"
        echo "  lpd8, lpd8_mk2            - LPD8 mk2 Editor"
        echo "  mpk261                    - MPK261 Editor"
        echo "  lpd8_mk3                  - LPD8 mk3 Editor (with RGB)"
        echo "  mpd226                    - MPD226 Editor (16 pads + 8 faders)"
        echo "  apc, apc_mini             - APC mini Editor (64-pad grid)"
        echo "  menu                      - Show this menu (default)"
        echo ""
        echo "Examples:"
        echo "  selahos-device-editors mpk"
        echo "  selahos-device-editors mpc_studio2"
        echo "  selahos-device-editors apc_mini"
        echo ""
        echo "Or from application menu:"
        echo "  Search for 'SelahOS Device Editor' in applications"
        echo ""

        # If PyQt6 is available, show GUI picker
        if python3 << 'PYTHON'
try:
    from PyQt6.QtWidgets import QApplication, QDialog, QVBoxLayout, QPushButton, QLabel, QGridLayout
    from PyQt6.QtCore import Qt
    import sys
    import subprocess

    class DeviceChooser(QDialog):
        def __init__(self):
            super().__init__()
            self.setWindowTitle("SelahOS Device Editors")
            self.setGeometry(100, 100, 500, 400)
            self.init_ui()

        def init_ui(self):
            layout = QVBoxLayout()

            label = QLabel("Select a device editor:")
            label.setStyleSheet("font-weight: bold; font-size: 12px; margin-bottom: 10px;")
            layout.addWidget(label)

            devices = [
                ("MPK mini IV", "mpk"),
                ("MPC Studio 2", "mpc"),
                ("LPD8 mk2", "lpd8"),
                ("MPK261", "mpk261"),
                ("LPD8 mk3 (RGB)", "lpd8_mk3"),
                ("MPD226", "mpd226"),
                ("APC mini (64 pads)", "apc"),
            ]

            for name, cmd in devices:
                btn = QPushButton(name)
                btn.clicked.connect(lambda checked, c=cmd: self.launch_device(c))
                layout.addWidget(btn)

            self.setLayout(layout)

        def launch_device(self, device):
            subprocess.Popen([sys.executable, sys.argv[0], device])
            self.close()

    if __name__ == '__main__':
        app = QApplication(sys.argv)
        window = DeviceChooser()
        window.show()
        sys.exit(app.exec())
except:
    sys.exit(1)
PYTHON
        then
            true
        fi
        ;;
esac
