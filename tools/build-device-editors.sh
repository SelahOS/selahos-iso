#!/bin/bash
#
# Build script for SelahOS Device Editors
# Creates distribution packages for all components

set -e

VERSION="${1:-1.0.0}"
OUTDIR="${2:-.}"
BUILDDIR="/tmp/selahos-build-$$"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Create build directory
log_info "Setting up build environment..."
mkdir -p "$BUILDDIR"
trap "rm -rf $BUILDDIR" EXIT

# ============================================================================
# Build Device Editors
# ============================================================================

log_info "Building device editors package..."
cd "$BUILDDIR"
mkdir -p device-editors-$VERSION/usr/local/bin
mkdir -p device-editors-$VERSION/usr/local/lib/selahos

# Copy editors
cp /home/dbnoble/selahos-iso-build/tools/device-editors/*.py \
   device-editors-$VERSION/usr/local/lib/selahos/

# Copy launcher
cp /home/dbnoble/selahos-iso-build/tools/device-editors/launcher.sh \
   device-editors-$VERSION/usr/local/bin/selahos-device-editors
chmod +x device-editors-$VERSION/usr/local/bin/selahos-device-editors

# Create tarball
tar -czf "$OUTDIR/device-editors-$VERSION.tar.gz" device-editors-$VERSION/
log_success "Created device-editors-$VERSION.tar.gz"

# ============================================================================
# Build Web Interface
# ============================================================================

log_info "Building web interface..."
cd device-editors-$VERSION

# Copy frontend
mkdir -p usr/local/share/selahos/web
if [ -d /home/dbnoble/selahos-iso-build/tools/device-editors-web/frontend/dist ]; then
    cp -r /home/dbnoble/selahos-iso-build/tools/device-editors-web/frontend/dist/* \
        usr/local/share/selahos/web/
else
    log_info "Building frontend from source..."
    cd /tmp/selahos-frontend-$$
    mkdir -p /tmp/selahos-frontend-$$

    # Build frontend
    (cd /home/dbnoble/selahos-iso-build/tools/device-editors-web/frontend && \
     npm install && npm run build)

    cp -r /home/dbnoble/selahos-iso-build/tools/device-editors-web/frontend/dist/* \
        $BUILDDIR/device-editors-$VERSION/usr/local/share/selahos/web/
fi

log_success "Web interface ready"

# ============================================================================
# Build Scripting Module
# ============================================================================

log_info "Building scripting module..."
cd "$BUILDDIR"
mkdir -p device-scripting-$VERSION/usr/local/lib/python3/dist-packages/selahos

# Copy scripting files
cp -r /home/dbnoble/selahos-iso-build/tools/device-editors-web/scripting/* \
      device-scripting-$VERSION/usr/local/lib/python3/dist-packages/selahos/

tar -czf "$OUTDIR/device-scripting-$VERSION.tar.gz" device-scripting-$VERSION/
log_success "Created device-scripting-$VERSION.tar.gz"

# ============================================================================
# Create package manifest
# ============================================================================

log_info "Creating package manifest..."
cat > "$OUTDIR/MANIFEST-$VERSION.txt" << 'EOF'
SelahOS Device Editors Release Manifest
Version: VERSION_PLACEHOLDER

Components:
1. device-editors-VERSION.tar.gz
   - 7 device editor applications
   - Unified launcher script
   - Installation script
   - Central dashboard

2. device-editors-web-VERSION.tar.gz
   - Vue.js web interface
   - REST API integration
   - Real-time device monitoring
   - MIDI port management

3. device-scripting-VERSION.tar.gz
   - Macro automation engine
   - Fluent builder API
   - REST API for execution
   - Pre-built templates

Installation:
1. Extract each archive to appropriate location
2. Update file permissions: chmod +x **/bin/*
3. Install Python dependencies: pip install PyQt6 fastapi uvicorn
4. Install Node dependencies (frontend): npm install

Documentation:
- Device Editors: tools/device-editors/README.md
- Web Interface: tools/device-editors-web/frontend/README.md
- Scripting: tools/device-editors-web/scripting/README.md

Support:
GitHub: https://github.com/SelahOS/selahos-iso
Issues: https://github.com/SelahOS/selahos-iso/issues
EOF

sed -i "s/VERSION_PLACEHOLDER/$VERSION/g" "$OUTDIR/MANIFEST-$VERSION.txt"
log_success "Created MANIFEST-$VERSION.txt"

# ============================================================================
# Create checksums
# ============================================================================

log_info "Creating checksums..."
cd "$OUTDIR"
sha256sum device-editors-*.tar.gz > CHECKSUMS-$VERSION 2>/dev/null || true
sha256sum device-scripting-*.tar.gz >> CHECKSUMS-$VERSION 2>/dev/null || true

# Verify
log_info "Verifying checksums..."
sha256sum -c CHECKSUMS-$VERSION

log_success "Checksum verification passed"

# ============================================================================
# Create summary
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           SelahOS Device Editors Build Complete              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Version: $VERSION"
echo "Output directory: $OUTDIR"
echo ""
echo "Generated files:"
ls -lh "$OUTDIR"/device-editors-*.tar.gz "$OUTDIR"/device-scripting-*.tar.gz 2>/dev/null || true
echo ""
echo "Installation:"
echo "  tar -xzf device-editors-$VERSION.tar.gz -C /"
echo "  tar -xzf device-scripting-$VERSION.tar.gz -C /"
echo ""
echo "Verify:"
echo "  selahos-device-editors --help"
echo "  python -c 'from selahos_scripting import *'"
echo ""
