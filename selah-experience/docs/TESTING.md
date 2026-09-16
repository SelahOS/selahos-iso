# Test gates

Run from selah-experience:

```sh
python3 tools/check.py
python3 tools/generate.py --check
python3 tools/test_plymouth.py
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software python3 tools/test_login.py
cd packaging && makepkg
```

The native Plymouth interpreter test uses the installed script.so with mock
display/image objects, not the daemon or console. It checks syntax and callback
state transitions; it does not prove initramfs, graphics, font or LUKS behavior.
The Qt test loads actual QML with fake SDDM models. No real login/power actions.

## Disposable VM / hardware gates before default activation

1. Snapshot a known working baseline, retain its boot entry and recovery media.
2. Install the package, but leave the existing themes selected initially.
3. Test both boot variants on a Plymouth-enabled VM. Use normal shutdown/boot,
   rapid boot, boot >12 seconds, Escape/details, failed service and shutdown.
4. Test LUKS password, wrong password, empty/long input and backspace, generic
   question prompts, boot messages, and switch back to normal display. Never
   capture real passwords. Verify no prompt is concealed by artwork.
5. Test text fallback without graphics, low resolution, HiDPI and multiple
   displays, hotplug, and a system that hands off before animation finishes.
6. Preview login with `sddm-greeter-qt6 --test-mode --theme
   /usr/share/sddm/themes/selah-experience`; no display-manager restart.
7. In a disposable VM only, select the login theme and test real PAM failure/
   success, user switching, empty-password policy, session persistence,
   keyboard layouts, Caps Lock, Tab/Shift-Tab/Enter, scrolling at 800x600,
   screen reader, and confirmed restart/shutdown.
8. Apply Plasma theme to a throwaway user. Confirm panels, apps, lock screen,
   shortcuts, compositor and multi-monitor behavior remain functional.
9. Verify uninstall/rollback with a reboot and fresh login. Measure the
   performance budgets against baseline. Block release on any regression.

The Beta 2.0.2 ISO may have older packages than the development machine.
Run the complete matrix against the actual release image before promotion.
