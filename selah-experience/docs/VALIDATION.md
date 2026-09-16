# Foundation validation — 2026-09-16

Environment: SelahOS development host, Python 3.14, Qt 6.11.2,
SDDM 0.21.0-7, Plasma workspace 6.7.4-3, Plymouth 26.134.222-2.

## Passed

- Source and staged payload checks: existing logo retained byte-for-byte;
  metadata, SVGs, PNG references, staging refusal for nonempty destinations.
- Plymouth decoded PNG memory: 713,280 bytes (<2MiB target).
- Both Plymouth scripts parsed and executed using the installed native
  script.so interpreter with mock graphics. Covered initial normal callback,
  bounded resonance, settled/no-redraw state, long boot, messages, 1,000-character
  password count capping, backspace, question/normal transitions, resize, quit.
- Generated assets match design tokens and source.
- Actual SDDM greeter loaded in offscreen test mode without QML load errors or
  binding loops. Test mode reports an expected unavailable daemon socket.
- Qt QML harness: initial remembered session, empty username, Enter-to-password,
  Enter-to-submit, failure recovery, password clearing, duplicate-submission
  guard, successful login signal, selected session forwarding, no-session
  guard, and 640x480 / 800x600 / 1920x1080 resize.
- qmllint passes. Only the four documented SDDM-injected context variables are
  exempted from unqualified-access lint; the rest of QML remains checked.
- Login preview rendered from actual QML at 1280x900 and visually inspected.
- KPackage installation/discovery passed in isolated XDG data/config directories;
  org.selah.desktop is recognized as Selah Experience (foundation).
- makepkg built the Arch package without installing it. Payload is namespaced
  under /usr/share, with no /etc files, activation scripts, services or hooks.
  Final package list/size is checked during handoff.
- Source changes are confined to selah-experience/. The working ISO profile
  remains unmodified by this task.

## Not yet qualified

Real Plymouth rendering/initramfs, LUKS input, Escape/details, early/slow boot,
multi-display/hotplug/HiDPI, power consumption and boot-time comparisons require
the disposable VM/hardware matrix in TESTING.md. Fake auth does not validate
PAM, actual session startup, accessibility or real power actions. No claim of
Beta 2.0.2 release qualification is made.

## Testing notes

An initial real-greeter ScrollView binding loop was fixed by giving ScrollView
an explicit Flickable. SDDM object accesses are guarded for teardown. An initial
Plymouth normal callback must not skip the entrance sequence; the native test
covers that case.

A custom --packageroot KPackage lookup showed Breeze fallback rather than our
package; retesting with an isolated XDG_DATA_HOME verified the actual package
identifier and metadata through the standard discovery path.

All development changes are on codex/selah-experience-beta2. No theme has been
selected, no package installed on the host, no initramfs rebuilt, no ISO built,
and no display manager restarted.
