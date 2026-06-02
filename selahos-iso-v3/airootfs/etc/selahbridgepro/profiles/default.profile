# SelahBridgePro — Default DAW Profile
# Balanced settings for general audio production.
# Sourced by: selahpro launch

# ── Wine runtime ────────────────────────────────────────────────
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

# ── SelahASIO / PipeWire ────────────────────────────────────────
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=256
# PIPEWIRE_LATENCY is set at launch time as "<buffer>/<rate>"
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ───────────────────────────────────────────────
WINEDLLOVERRIDES="wineasio=n,b;msacm32=n,b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── Registry tweaks applied at first launch ─────────────────────
# (applied by selahpro via selahwine regedit before DAW launch)
SELAH_REG_APPLY=1
