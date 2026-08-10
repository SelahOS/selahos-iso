#!/bin/bash
#
# SelahOS ISO Integration - Device Editors Installation
# This script integrates device editors into the SelahOS ISO build

set -e

VERSION="${1:-1.0.0}"
AIROOTFS="${2:-$(pwd)/selahos-iso-v3/airootfs}"
DEVICE_EDITORS_SRC="$(pwd)/tools/device-editors"
WEB_INTERFACE_SRC="$(pwd)/tools/device-editors-web"
SCRIPTING_SRC="$(pwd)/tools/device-editors-web/scripting"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[*]${NC} $1"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $1"; }

# ============================================================================
# Install Device Editors
# ============================================================================

log_info "Installing device editors to ISO..."

# Create directories
mkdir -p "$AIROOTFS/usr/local/bin"
mkdir -p "$AIROOTFS/usr/local/lib/selahos"
mkdir -p "$AIROOTFS/usr/share/applications"
mkdir -p "$AIROOTFS/etc/selahos"

# Copy editor scripts
cp "$DEVICE_EDITORS_SRC"/*.py "$AIROOTFS/usr/local/lib/selahos/"
cp "$DEVICE_EDITORS_SRC/launcher.sh" "$AIROOTFS/usr/local/bin/selahos-device-editors"
chmod +x "$AIROOTFS/usr/local/bin/selahos-device-editors"

log_ok "Device editors installed"

# ============================================================================
# Install Web Interface
# ============================================================================

log_info "Installing web interface to ISO..."

mkdir -p "$AIROOTFS/usr/share/selahos/web"

# Copy built frontend (or build if not present)
if [ -d "$WEB_INTERFACE_SRC/frontend/dist" ]; then
    cp -r "$WEB_INTERFACE_SRC/frontend/dist"/* "$AIROOTFS/usr/share/selahos/web/"
    log_ok "Web interface installed from dist/"
else
    log_info "Building web interface from source..."
    (cd "$WEB_INTERFACE_SRC/frontend" && npm install && npm run build)
    cp -r "$WEB_INTERFACE_SRC/frontend/dist"/* "$AIROOTFS/usr/share/selahos/web/"
    log_ok "Web interface built and installed"
fi

# ============================================================================
# Install Scripting Module
# ============================================================================

log_info "Installing scripting module to ISO..."

mkdir -p "$AIROOTFS/usr/lib/python3/dist-packages/selahos_scripting"

cp -r "$SCRIPTING_SRC/core" "$AIROOTFS/usr/lib/python3/dist-packages/selahos_scripting/"
cp "$SCRIPTING_SRC"/*.py "$AIROOTFS/usr/lib/python3/dist-packages/selahos_scripting/"
cp "$SCRIPTING_SRC/__init__.py" "$AIROOTFS/usr/lib/python3/dist-packages/selahos_scripting/"

log_ok "Scripting module installed"

# ============================================================================
# Create Systemd Service
# ============================================================================

log_info "Creating systemd service..."

mkdir -p "$AIROOTFS/etc/systemd/system"

cat > "$AIROOTFS/etc/systemd/system/selahos-device-bridge.service" << 'EOF'
[Unit]
Description=SelahOS Device Bridge
Documentation=https://github.com/SelahOS/selahos-iso
After=network.target sound.target
Wants=selahos-mpc-bridge.service

[Service]
Type=simple
Environment="PYTHONUNBUFFERED=1"
ExecStart=/usr/bin/python /usr/local/lib/selahos/selahos-central-dashboard.py
Restart=on-failure
RestartSec=5
User=selahos
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log_ok "Systemd service created"

# ============================================================================
# Create Desktop Entries
# ============================================================================

log_info "Creating desktop entries..."

cat > "$AIROOTFS/usr/share/applications/selahos-device-editors.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SelahOS Device Editors
Comment=Control Akai Professional MIDI controllers
Exec=selahos-device-editors
Icon=selahos
Categories=AudioVideo;Mixer;Audio;
Keywords=midi;akai;controller;mpk;mpc;
Terminal=false
EOF

cat > "$AIROOTFS/usr/share/applications/selahos-device-bridge-web.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SelahOS Device Bridge
Comment=Web interface for device control
Exec=firefox http://localhost:8000
Icon=selahos
Categories=AudioVideo;Network;
Keywords=midi;web;device;bridge;
Terminal=false
EOF

log_ok "Desktop entries created"

# ============================================================================
# Create Configuration
# ============================================================================

log_info "Creating configuration files..."

mkdir -p "$AIROOTFS/etc/selahos/device-bridge"

cat > "$AIROOTFS/etc/selahos/device-bridge/config.ini" << 'EOF'
[bridge]
enabled = true
port = 8000
host = 0.0.0.0
api_version = 1.0

[devices]
auto_initialize = true
auto_detect = true

[web]
enabled = true
static_dir = /usr/share/selahos/web
document_root = /usr/share/selahos/web

[scripting]
enabled = true
macro_dir = ~/.config/selahos/macros
auto_load = true

[logging]
level = info
file = /var/log/selahos/device-bridge.log
EOF

log_ok "Configuration created"

# ============================================================================
# Create Boot Integration Script
# ============================================================================

log_info "Creating boot integration script..."

mkdir -p "$AIROOTFS/etc/selahos/boot.d"

cat > "$AIROOTFS/etc/selahos/boot.d/10-device-bridge" << 'EOF'
#!/bin/bash
# SelahOS Device Bridge Boot Integration

echo "Initializing SelahOS Device Bridge..."

# Load configuration
if [ -f /etc/selahos/device-bridge/config.ini ]; then
    source <(grep -E "^[a-zA-Z_]" /etc/selahos/device-bridge/config.ini | sed 's/ = /=/g')
fi

# Start device bridge service
if systemctl is-enabled selahos-device-bridge.service >/dev/null 2>&1; then
    systemctl start selahos-device-bridge.service
    echo "✓ Device Bridge started"
fi

# Initialize connected devices
if [ "$auto_initialize" = "true" ]; then
    echo "Detecting and initializing devices..."
    sleep 2

    # This would call device initialization script
    if [ -f /usr/local/bin/selahos-device-init ]; then
        /usr/local/bin/selahos-device-init
    fi
fi

echo "Device Bridge ready"
EOF

chmod +x "$AIROOTFS/etc/selahos/boot.d/10-device-bridge"

log_ok "Boot integration script created"

# ============================================================================
# Create Udev Rules Integration
# ============================================================================

log_info "Creating udev rules..."

mkdir -p "$AIROOTFS/etc/udev/rules.d"

cat > "$AIROOTFS/etc/udev/rules.d/80-selahos-devices.rules" << 'EOF'
# SelahOS Device Bridge - Akai Professional Controller Hotplug Rules

# Akai VID (09E8)
SUBSYSTEM=="usb", ATTR{idVendor}=="09e8", MODE="0666"

# MIDI devices
SUBSYSTEM=="sound", TAG="udev-acl", TAG+="uaccess"

# Generic ALSA sequencer
SUBSYSTEM=="snd", KERNEL=="seq", MODE="0666"
EOF

log_ok "Udev rules created"

# ============================================================================
# Package List Integration
# ============================================================================

log_info "Preparing package list integration..."

# Backup original packages file
if [ -f "$AIROOTFS/../packages.x86_64" ]; then
    cp "$AIROOTFS/../packages.x86_64" "$AIROOTFS/../packages.x86_64.bak"
    log_ok "Packages file backed up"
fi

# Add required packages if not already present
PACKAGES_FILE="$AIROOTFS/../packages.x86_64"

for pkg in python-pyqt6 python-mido python-fastapi python-uvicorn python-pydantic; do
    if ! grep -q "^$pkg$" "$PACKAGES_FILE"; then
        echo "$pkg" >> "$PACKAGES_FILE"
        log_ok "Added $pkg to packages"
    fi
done

# ============================================================================
# Build Summary
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   SelahOS Device Bridge ISO Integration Complete              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Installed Components:"
echo "  ✓ 7 Device Editors"
echo "  ✓ Web Interface (Vue.js)"
echo "  ✓ Scripting Module"
echo "  ✓ Systemd Service"
echo "  ✓ Desktop Entries"
echo "  ✓ Boot Scripts"
echo "  ✓ Udev Rules"
echo "  ✓ Configuration"
echo ""
echo "AIROOTFS: $AIROOTFS"
echo ""
echo "To rebuild ISO:"
echo "  cd selahos-iso-v3"
echo "  sudo mkarchiso -v -o ~/Images/ ."
echo ""
echo "Next steps:"
echo "  1. Review integration by inspecting AIROOTFS"
echo "  2. Build ISO image"
echo "  3. Test in VM or hardware"
echo "  4. Verify services start correctly"
echo ""
