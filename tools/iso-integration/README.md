# SelahOS ISO Integration Guide

Complete integration of Device Bridge components into SelahOS ISO build.

## Overview

This integration includes:
- Device Editor GUI applications
- Web interface (Vue.js + FastAPI)
- Macro scripting system
- Systemd services
- Boot integration
- Udev rules for hotplug
- Desktop entries
- Configuration framework

## Quick Start

```bash
# Run integration script
./tools/iso-integration/install-device-editors.sh 1.0.0 ./selahos-iso-v3/airootfs

# Rebuild ISO
cd selahos-iso-v3
sudo mkarchiso -v -o ~/Images/ .
```

## Components Installed

### Device Editors
- Location: `/usr/local/lib/selahos/*.py`
- Launcher: `/usr/local/bin/selahos-device-editors`
- 7 GUI applications for Akai controllers

### Web Interface
- Location: `/usr/share/selahos/web/`
- Backend: FastAPI (bundled with editors)
- Frontend: Static Vue.js build
- Default: http://localhost:8000

### Scripting Module
- Location: `/usr/lib/python3/dist-packages/selahos_scripting/`
- Python module for macro automation
- CLI tool: `selahos-macro`
- REST API integration

### Services
- `selahos-device-bridge.service` - Main bridge service
- Auto-start: Enabled by default
- User: `selahos`

### Boot Integration
- Script: `/etc/selahos/boot.d/10-device-bridge`
- Auto-detect devices on boot
- Auto-initialize if configured
- Logging to `/var/log/selahos/`

### Configuration
- Main config: `/etc/selahos/device-bridge/config.ini`
- Boot scripts: `/etc/selahos/boot.d/`
- Udev rules: `/etc/udev/rules.d/80-selahos-devices.rules`

## Manual Integration Steps

If not using the integration script:

### 1. Copy Files

```bash
AIROOTFS=./selahos-iso-v3/airootfs

# Editors
cp -r tools/device-editors/*.py $AIROOTFS/usr/local/lib/selahos/

# Web interface
cp -r tools/device-editors-web/frontend/dist/* $AIROOTFS/usr/share/selahos/web/

# Scripting
cp -r tools/device-editors-web/scripting/* \
      $AIROOTFS/usr/lib/python3/dist-packages/selahos_scripting/
```

### 2. Create Service File

```bash
# Copy systemd service
cp tools/iso-integration/systemd/* $AIROOTFS/etc/systemd/system/
```

### 3. Add Packages

Edit `selahos-iso-v3/packages.x86_64`:
```
python-pyqt6
python-mido
python-fastapi
python-uvicorn
python-pydantic
```

### 4. Add Boot Hook

Edit `selahos-iso-v3/airootfs/root/customize_airootfs.sh`:
```bash
# Enable device bridge service
systemctl enable selahos-device-bridge.service
```

## Configuration

Edit `/etc/selahos/device-bridge/config.ini`:

```ini
[bridge]
enabled = true          # Enable/disable bridge
port = 8000            # API port
host = 0.0.0.0         # Bind address

[devices]
auto_initialize = true # Auto-init on boot
auto_detect = true     # Detect devices

[web]
enabled = true         # Enable web interface
static_dir = /usr/share/selahos/web
document_root = /usr/share/selahos/web

[scripting]
enabled = true         # Enable macros
macro_dir = ~/.config/selahos/macros
auto_load = true       # Load saved macros

[logging]
level = info           # Log level: debug, info, warning, error
file = /var/log/selahos/device-bridge.log
```

## First Boot Experience

After installing ISO:

1. **Device Detection**
   - Bridge auto-starts on boot
   - Scans for connected devices
   - Initializes hardware if configured

2. **Services Available**
   - Web interface: http://localhost:8000
   - CLI tools: `selahos-device-editors`
   - Python module: `from selahos_scripting import *`

3. **User Setup**
   - Create user config: `~/.config/selahos/`
   - Save macros: `~/.config/selahos/macros/`
   - Customize: `/etc/selahos/device-bridge/`

## Systemd Services

### Device Bridge Service

```bash
# Check status
systemctl status selahos-device-bridge

# Start/stop
systemctl start selahos-device-bridge
systemctl stop selahos-device-bridge

# Enable on boot
systemctl enable selahos-device-bridge

# View logs
journalctl -u selahos-device-bridge -f
```

### Related Services

```bash
# MIDI sequencer
systemctl status selahos-midi-seq

# MPC bridge
systemctl status selahos-mpc-bridge
```

## Boot Integration Script

Location: `/etc/selahos/boot.d/10-device-bridge`

Runs during boot to:
1. Load configuration
2. Detect connected devices
3. Initialize hardware
4. Start related services

Execution order:
1. Network ready
2. Sound system ready
3. MIDI sequencer ready
4. Device detection
5. Service startup

## Udev Rules

File: `/etc/udev/rules.d/80-selahos-devices.rules`

Provides:
- Automatic device detection on hotplug
- Permission management (666)
- MIDI device support
- ALSA sequencer access

## Desktop Integration

### Desktop Entries

1. **Device Editors** (`selahos-device-editors.desktop`)
   - Launch device editor menu
   - Category: AudioVideo/Mixer
   - Icon: selahos

2. **Device Bridge** (`selahos-device-bridge-web.desktop`)
   - Open web interface
   - Category: AudioVideo/Network
   - Opens: http://localhost:8000

### Launcher Integration

Add to application menu:
```bash
# Edit menu config
nano ~/.config/openbox/menu.xml

# Add entry
<menu id="audio" label="Audio">
  <item label="Device Editors">
    <action name="Execute">
      <command>selahos-device-editors</command>
    </action>
  </item>
  <item label="Device Bridge">
    <action name="Execute">
      <command>firefox http://localhost:8000</command>
    </action>
  </item>
</menu>
```

## Package Dependencies

Required packages added to ISO:

```
python-pyqt6       - GUI framework
python-mido        - MIDI library
python-fastapi     - Web framework
python-uvicorn     - ASGI server
python-pydantic    - Data validation
```

Optional packages:
- `nginx` - For reverse proxy
- `nodejs` - For web development
- `firefox` - To access web interface

## Troubleshooting

### Service Won't Start

```bash
# Check logs
journalctl -u selahos-device-bridge -n 50

# Verify dependencies
pacman -Qk python-pyqt6

# Test manually
python /usr/local/lib/selahos/selahos-central-dashboard.py
```

### Devices Not Detected

```bash
# Check udev rules
udevadm test /sys/devices/pci0000:00/...

# Reload rules
sudo udevadm control --reload
sudo udevadm trigger

# Check dmesg
dmesg | grep -i usb
```

### Web Interface Not Accessible

```bash
# Check if service running
systemctl status selahos-device-bridge

# Check port
netstat -tlnp | grep 8000

# Verify firewall
sudo firewall-cmd --list-ports
```

## Testing Integration

### Pre-ISO Test

```bash
# Install locally
./tools/iso-integration/install-device-editors.sh 1.0.0 ./test-airootfs

# Verify files
ls -la test-airootfs/usr/local/lib/selahos/
ls -la test-airootfs/usr/share/selahos/web/
ls -la test-airootfs/etc/systemd/system/selahos-device-bridge.service
```

### Post-ISO Test

Boot ISO and verify:

1. Services started
   ```bash
   systemctl list-units --state=running | grep selahos
   ```

2. Devices detected
   ```bash
   lsusb | grep -i akai
   ```

3. Web interface
   ```bash
   curl http://localhost:8000
   ```

4. Python module
   ```bash
   python -c "from selahos_scripting import *; print('OK')"
   ```

## Performance Considerations

### Boot Time
- Bridge service adds ~3-5 seconds
- Device detection adds ~2-3 seconds
- Web interface lazy-loads (no impact)

### Memory Usage
- Bridge process: ~50-100 MB
- Web interface: ~20 MB (static)
- Scripting module: ~10 MB

### Disk Space
- Device editors: ~5 MB
- Web interface: ~2 MB
- Scripting module: ~1 MB
- Total: ~8 MB additional

## Future Enhancements

- [ ] GUI setup wizard on first boot
- [ ] Hardware detection notification
- [ ] Automatic driver installation
- [ ] Desktop preferences integration
- [ ] Flatpak packaging support
- [ ] systemd-nspawn container support

## Support

For issues:
1. Check systemd logs: `journalctl -u selahos-device-bridge`
2. Check dmesg for hardware issues: `dmesg`
3. Verify configuration: `/etc/selahos/device-bridge/config.ini`
4. Report on GitHub: https://github.com/SelahOS/selahos-iso/issues

## Documentation

- Device Editors: `/usr/share/doc/selahos-device-editors/`
- Web Interface: `/usr/share/doc/selahos-device-bridge/`
- Scripting: `/usr/share/doc/selahos-device-scripting/`
- Main repo: https://github.com/SelahOS/selahos-iso
