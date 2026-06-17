# SelahBridgePro -- Windows Apps Profile
# General-purpose profile for Electron and productivity apps (non-DAW).
# No WineASIO / ASIO audio routing -- apps in this profile don't produce
# audio through the DAW path.

# -- Wine runtime ------------------------------------------------------------
# ESYNC/FSYNC disabled: causes window-creation hangs in Electron utility
# processes (e.g. SparkCore subprocess never creates its window).
WINEESYNC=0
WINEFSYNC=0
WINE_LARGE_ADDRESS_AWARE=1
WINE_DISABLE_CRASH_REPORT=1
WINEDEBUG=-all
WINE_WINDOWS_VERSION=win10
WINEARCH=win64

# -- Display: force XWayland -------------------------------------------------
# Wine 11+ defaults to the native Wayland driver when WAYLAND_DISPLAY is set,
# but that backend silently drops window creation for Electron utility processes.
DISPLAY=:1
WAYLAND_DISPLAY=

# -- DXVK / VKD3D disabled for non-DAW apps ---------------------------------
# DXVK (d3d11=n) crashes SparkCore's Swift subprocess (exit 0xC0000CD0).
SELAH_DXVK_ENABLED=0
SELAH_VKD3D_ENABLED=0

# -- No ASIO for non-DAW apps ------------------------------------------------
SELAH_ASIO_ENABLED=0

# -- DLL overrides -----------------------------------------------------------
WINEDLLOVERRIDES="winemenubuilder.exe=d"

# -- Registry tweaks applied once at first launch ----------------------------
SELAH_REG_APPLY=1
