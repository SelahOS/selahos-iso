# SelahBridgePro — Ableton Live Profile
# Ableton Live 11/12 via Wine.
# Live has strict audio threading requirements; fsync is critical.

# ── Wine runtime overrides ──────────────────────────────────────
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
WINEDEBUG=-all,+midi
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# ── DXVK ────────────────────────────────────────────────────────
DXVK_ASYNC=1
DXVK_FRAME_RATE=60
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# ── SelahASIO / PipeWire — Live works best at 256 samples ───────
SELAH_AUDIO_RATE=44100
SELAH_AUDIO_BUFFER=256
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ───────────────────────────────────────────────
# wineasio: ASIO driver
# mmdevapi: force native audio subsystem routing
# dsound: built-in dsound routes through WineASIO
WINEDLLOVERRIDES="wineasio=n,b;mmdevapi=b;dsound=b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── Ableton executable ──────────────────────────────────────────
SELAH_DAW_EXE="Ableton Live 12 Suite.exe"
SELAH_DAW_NAME="Ableton Live"
SELAH_REG_APPLY=1
