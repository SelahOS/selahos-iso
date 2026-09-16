# Implementation references

Checked 2026-09-16, alongside the installed native packages:

- SDDM theming/context API:
  https://github.com/sddm/sddm/wiki/Theming
- SDDM configuration precedence:
  https://github.com/sddm/sddm/blob/develop/data/man/sddm.conf.rst.in
- Plasma Look-and-Feel package structure and Breeze fallback:
  https://invent.kde.org/plasma/plasma-workspace/-/blob/master/shell/packageplugins/lookandfeel/lookandfeel.cpp
- Plymouth native script syntax/API and 50Hz default:
  https://gitlab.freedesktop.org/plymouth/plymouth/-/tree/main/src/plugins/splash/script
- Installed /usr/share/plymouth/themes/script/script.script:
  used to confirm the password, normal, progress, message and quit callbacks.
- Installed KPackage tooling:
  used to verify metadata.json and KPackageStructure=Plasma/LookAndFeel.
  No speculative manifest.json or Plasma fork is introduced.

Upstream docs can move ahead of Beta 2.0.2; the release ISO remains the
compatibility test target.
