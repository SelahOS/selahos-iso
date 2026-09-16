# Local Arch packaging

Run `makepkg` here, as a normal user, from the complete source checkout.
This follows the repository's local packaging model: files are staged from
`$startdir/..`; it is NOT a standalone AUR recipe. `makepkg -S` alone does
not produce a usable source release. For a release, first archive the complete
committed selah-experience tree and add a pinned source URL and checksum.

Python is build-only. Committed PNG/QML/script assets avoid a Qt/Python runtime
dependency for boot. Regeneration requires python-pyqt6 and qt6-svg separately.
Runtime dependencies are optional because each component can be used alone;
install the listed prerequisites for the component being tested.

No .install script is needed: packaging owns only files under /usr/share.
There are no activation hooks or initramfs rebuilds. Existing selah-theme,
its /etc/sddm.conf.d configuration and existing theme IDs are not replaced.
Deactivate every selected component BEFORE removing this package.
