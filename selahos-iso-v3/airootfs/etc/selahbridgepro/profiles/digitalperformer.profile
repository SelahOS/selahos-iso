# SelahBridgePro — Digital Performer Profile
# MOTU Digital Performer 11.x via Wine
#
# Crash analysis (2026-06-01 backtrace):
#   - Root cause 1: WINEARCH was win32; DP 11 is 64-bit only
#   - Root cause 2: msvcp140+0x13080 null vtable (std::function on empty
#     license callback from motucorelibs) — fixed by native VC++ redist
#   - Root cause 3: LDSvc.exe COM race on startup — fixed by pre-launch delay
#
# Required setup:
#   selahpro install dp    (runs winetricks vcredist2022 automatically)

# ── Wine runtime ────────────────────────────────────────────────
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
# loaddll debug helps catch CRT mismatch on first run; disable after confirmed working
WINEDEBUG=-all,+loaddll
WINE_WINDOWS_VERSION=win10

# DP 11 is 64-bit only — must be win64 or the LDSvc COM registration breaks
WINEARCH=win64

# ── DXVK ────────────────────────────────────────────────────────
DXVK_ASYNC=1
DXVK_FRAME_RATE=0
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# ── SelahASIO / PipeWire ────────────────────────────────────────
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=256
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides (critical — fixes msvcp140 null vtable crash) ─
# All four CRT components must be native to maintain ABI consistency
# with the native motucorelibs.dll binaries inside DP's install dir.
# vcredist2022 provides: msvcp140, vcruntime140, vcruntime140_1, ucrtbase
WINEDLLOVERRIDES="msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b;ucrtbase=n,b;wineasio=n,b;msacm32=n,b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── DP pre-launch services ──────────────────────────────────────
# LDSvc.exe (MOTU license daemon) must be running and its COM server
# must finish registering before DP.exe calls into motucorelibs.
# selahpro launch dp handles this automatically via SELAH_PRELAUNCHES.
SELAH_PRELAUNCHES="LDSvc.exe"
SELAH_PRELAUNCH_WAIT=4

# ── DP executable ───────────────────────────────────────────────
SELAH_DAW_EXE="DP.exe"
SELAH_DAW_NAME="Digital Performer"
SELAH_REG_APPLY=1
SELAH_REG_EXTRA="/usr/share/selahbridgepro/selahwine-dp-fixes.reg"
