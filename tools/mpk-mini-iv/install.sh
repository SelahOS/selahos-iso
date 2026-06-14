#!/usr/bin/env bash
# Install MPK mini IV Editor for SelahOS
# Run as root (or with sudo).
set -e

DEST_LIB=/usr/local/lib/mpk-mini-iv
DEST_BIN=/usr/local/bin/mpk-mini-iv-editor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing MPK mini IV Editor…"

mkdir -p "$DEST_LIB"
cp "$SCRIPT_DIR/mpk_midi_core.py"       "$DEST_LIB/"
cp "$SCRIPT_DIR/mpk_mini_iv_editor.py"  "$DEST_LIB/"

cat > "$DEST_BIN" << 'EOF'
#!/usr/bin/env bash
exec python3 /usr/local/lib/mpk-mini-iv/mpk_mini_iv_editor.py "$@"
EOF
chmod +x "$DEST_BIN"

echo "==> Installing udev rules…"
cp "$SCRIPT_DIR/99-mpk-mini-iv.rules" /etc/udev/rules.d/
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=usb 2>/dev/null || true

echo "==> Installing desktop entry…"
cp "$SCRIPT_DIR/mpk-mini-iv-editor.desktop" /usr/share/applications/
update-desktop-database /usr/share/applications/ 2>/dev/null || true

echo "==> Installing Python dependencies (mido, python-rtmidi)…"
pip install --break-system-packages --quiet mido python-rtmidi

echo ""
echo "Done! Launch with:  mpk-mini-iv-editor"
echo "Or search 'MPK mini IV Editor' in your app launcher."
echo ""
echo "SelahBridgePro note:"
echo "  The MPK mini IV is class-compliant — Wine DAWs see it via the"
echo "  WineASIO MIDI bridge automatically (no extra config needed)."
