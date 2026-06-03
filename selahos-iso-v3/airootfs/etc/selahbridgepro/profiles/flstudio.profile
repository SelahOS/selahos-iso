# SelahBridgePro — FL Studio Profile
# FL Studio 21+ via Wine. Works well; native Linux binaries also
# available but Wine version has better VST2/VST3 plugin compat.
# Inherits defaults from default.profile.

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

# ── SelahASIO / PipeWire — FL Studio uses 512 buffer by default ─
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=512
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ───────────────────────────────────────────────
# wineasio: ASIO driver
# msacm32: audio codec manager (FL uses it for MP3 decode)
# ucrtbase: use native CRT for FL's .NET-adjacent components
WINEDLLOVERRIDES="wineasio=n,b;msacm32=n,b;ucrtbase=n,b"

# ── USB MIDI ────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

# ── FL Studio executable ────────────────────────────────────────
SELAH_DAW_EXE="FL64.exe"
SELAH_DAW_NAME="FL Studio"
SELAH_REG_APPLY=1
