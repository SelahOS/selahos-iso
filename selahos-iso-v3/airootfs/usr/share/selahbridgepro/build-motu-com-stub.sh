#!/usr/bin/env bash
# build-motu-com-stub.sh — Build and register the MOTU COM stub DLL
#
# Requires: mingw-w64-gcc (pacman -S mingw-w64-gcc)
# Usage: bash build-motu-com-stub.sh [WINEPREFIX]
#
# Selah Technologies LLC — SelahBridgePro project

set -euo pipefail

PREFIX="${1:-${WINEPREFIX:-$HOME/.wine}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/motu_com_stub.c"
DLL_NAME="motu_com_stub.dll"
OUT_DIR="$PREFIX/drive_c/windows/system32"
OUT_DLL="$OUT_DIR/$DLL_NAME"

echo "[SelahBridgePro] Building $DLL_NAME ..."
x86_64-w64-mingw32-gcc \
    -shared \
    -o "$OUT_DLL" \
    "$SRC" \
    -lole32 \
    -O2 \
    -Wall \
    -Wl,--subsystem,windows \
    -Wl,--kill-at

echo "[SelahBridgePro] Registering CLSID {E6BADE5B-E703-4672-B167-4AC9C9206747} ..."
REG_FILE="$(mktemp /tmp/motu_stub_XXXXXX.reg)"
cat > "$REG_FILE" << 'REGEOF'
REGEDIT4

[HKEY_LOCAL_MACHINE\Software\Classes\CLSID\{E6BADE5B-E703-4672-B167-4AC9C9206747}]
@="MOTU Audio System Stub"

[HKEY_LOCAL_MACHINE\Software\Classes\CLSID\{E6BADE5B-E703-4672-B167-4AC9C9206747}\InProcServer32]
@="C:\\windows\\system32\\motu_com_stub.dll"
"ThreadingModel"="Both"
REGEOF

WINEPREFIX="$PREFIX" wine regedit "$REG_FILE"
rm -f "$REG_FILE"

echo "[SelahBridgePro] Done. MOTU COM stub installed to $OUT_DLL"
