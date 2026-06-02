# SelahBridgePro — Pro Tools Profile
# Pro Tools First / Pro Tools via Wine.
#
# NOTE: Pro Tools uses PACE/iLok DRM which has extremely limited
# Wine support as of 2026. This profile provides the best-known
# environment for Pro Tools First (which has reduced DRM).
# Full Pro Tools with iLok hardware requires ongoing community work.
# Monitor: https://appdb.winehq.org — search "Pro Tools"

# ── Wine runtime overrides ──────────────────────────────────────
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
# Pro Tools needs some debug output for DRM troubleshooting
WINEDEBUG=-all,+loaddll,+midi
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# ── DXVK ────────────────────────────────────────────────────────
DXVK_ASYNC=1
DXVK_FRAME_RATE=60
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# ── SelahASIO / PipeWire ────────────────────────────────────────
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=256
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ───────────────────────────────────────────────
# comdlg32, ole32: Pro Tools installer/dialogs need native
# wineasio: ASIO driver
WINEDLLOVERRIDES="wineasio=n,b;comdlg32=n,b;ole32=n,b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── Pro Tools executable ─────────────────────────────────────────
SELAH_DAW_EXE="Pro Tools.exe"
SELAH_DAW_NAME="Pro Tools"
SELAH_REG_APPLY=1
