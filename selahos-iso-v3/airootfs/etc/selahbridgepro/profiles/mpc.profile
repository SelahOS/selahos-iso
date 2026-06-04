# SelahBridgePro — MPC Software Profile
# Akai MPC Software 2.x / 3.x via Wine
#
# Hardware: MPC Studio 2 (VID:09e8 PID:004a)
# Display and RGB pad LED control require hidraw access — granted by
# /etc/udev/rules.d/99-selah-midi.rules (SUBSYSTEM=="hidraw" block).
#
# Required setup:
#   selahpro install mpc    (runs winetricks deps automatically)
#   selahpro midi passthrough mpc   (ensures hidraw udev rules are active)

# ── Wine runtime ─────────────────────────────────────────────────
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
WINEDEBUG=-all
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# ── DXVK ─────────────────────────────────────────────────────────
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
# MPC Software ships with native VC++ 2019 CRT binaries; force native
# so Wine's built-in CRT doesn't cause ABI mismatches at runtime.
WINEDLLOVERRIDES="msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b;wineasio=n,b;msacm32=n,b"

# ── USB MIDI + HID passthrough ───────────────────────────────────
SELAH_MIDI_PASSTHROUGH=1
SELAH_MIDI_SYSEX=1
SELAH_HID_PASSTHROUGH=1

# ── MPC Software executable ──────────────────────────────────────
SELAH_DAW_EXE="MPC.exe"
SELAH_DAW_NAME="MPC Software"
SELAH_INSTALL_PATH="C:/Program Files/Akai Professional/MPC"
