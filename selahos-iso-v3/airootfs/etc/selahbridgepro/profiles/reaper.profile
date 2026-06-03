# SelahBridgePro — REAPER Profile
# REAPER 7+ via Wine. REAPER also has a native Linux build, but the
# Wine version provides better Windows VST3 plugin compatibility.
# REAPER is the most Wine-compatible DAW — lowest latency achievable.

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
DXVK_FRAME_RATE=0
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# ── SelahASIO / PipeWire — REAPER can negotiate down to 64 buf ──
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=128
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ───────────────────────────────────────────────
WINEDLLOVERRIDES="wineasio=n,b;msacm32=n,b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── REAPER executable ───────────────────────────────────────────
SELAH_DAW_EXE="reaper.exe"
SELAH_DAW_NAME="REAPER"
SELAH_REG_APPLY=1
