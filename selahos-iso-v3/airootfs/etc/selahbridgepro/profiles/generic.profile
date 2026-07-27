# SelahBridgePro -- Generic Windows App Profile (SELAH-40 Ultimate foundation)
# Used by: selahpro prefix create / run / install-app / selahbridge-detect
#
# Balanced settings for arbitrary non-DAW Windows apps and installers, not
# just the DAWs that have their own dedicated profile. DXVK/VKD3D stay
# enabled by default: many non-Electron utility apps (license managers,
# plugin installers, .NET/WPF tools) render through D3D11 and silently
# misbehave without it -- see Studio One 7's entry in app-compat-db.json for
# a documented example of that exact symptom ("Windows 10 required" even
# though Wine already reports win10).
#
# Apps that specifically crash WITH DXVK/ESYNC -- Electron apps like Spark
# Desktop -- should keep using the "apps" profile instead, not this one.

# -- Wine runtime ------------------------------------------------------------
WINEESYNC=1
WINEFSYNC=1
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
WINEDEBUG=-all
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# -- DXVK (D3D9/10/11 -> Vulkan) ----------------------------------------------
DXVK_ASYNC=1
DXVK_FRAME_RATE=0
DXVK_LOG_LEVEL=none
DXVK_STATE_CACHE=1

# -- VKD3D-Proton (D3D12 -> Vulkan) -------------------------------------------
VKD3D_CONFIG=upload_hvv
VKD3D_FEATURE_LEVEL=12_0
VKD3D_LOG_LEVEL=none

# -- No ASIO by default -- most non-DAW utility apps don't route audio -------
SELAH_ASIO_ENABLED=0

# -- DLL overrides -------------------------------------------------------------
WINEDLLOVERRIDES="winemenubuilder.exe=d"

# -- Registry tweaks applied once at first launch -----------------------------
SELAH_REG_APPLY=1
