# SelahBridgePro — Studio One 7 Profile
# PreSonus Studio One 7 via Wine-Staging + DXVK.
# Studio One 7 requires Direct3D 11 for GPU-accelerated UI rendering;
# DXVK is mandatory — without it the GPU check fails with "Windows 10 required".

# ── Wine runtime ─────────────────────────────────────────────────
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
WINEDEBUG=-all
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# ── DXVK (D3D11 → Vulkan) ────────────────────────────────────────
DXVK_ASYNC=1
DXVK_FRAME_RATE=0
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# ── SelahASIO / PipeWire ─────────────────────────────────────────
SELAH_AUDIO_RATE=48000
SELAH_AUDIO_BUFFER=256
SELAH_ASIO_ENABLED=1
SELAH_ASIO_DRIVER=wineasio
SELAH_ASIO_PIPEWIRE_DIRECT=1

# ── DLL overrides ────────────────────────────────────────────────
WINEDLLOVERRIDES="wineasio=n,b;msacm32=n,b"

# ── USB MIDI ─────────────────────────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1

SELAH_DAW_NAME="Studio One 7"
SELAH_REG_APPLY=1
