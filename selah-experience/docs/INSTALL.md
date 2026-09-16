# Install, preview, activate, rollback

## Safe default

Building or installing the package does not select any theme. Do not change the
shipping ArchISO profile, boot loader, installer, liveuser autologin or initramfs
hooks for this foundation. Current profile has no Plymouth hook.

Build as dbnoble:
```sh
cd /home/dbnoble/Development/selahos/selah-experience/packaging
makepkg
```
Review the package with `bsdtar -tf selah-experience-0.1.0-1-any.pkg.tar.zst`.
On a disposable target, install with:
```sh
sudo pacman -U ./selah-experience-0.1.0-1-any.pkg.tar.zst
```
This creates only namespaced /usr/share files; it does not start or stop services.

## Plymouth: only on a target where Plymouth already works

First snapshot the VM, record `plymouth-set-default-theme` output, and back up
`/etc/plymouth/plymouthd.conf` (record whether it existed), the existing
initramfs images and relevant /etc/mkinitcpio configuration. Keep a known working
boot entry. Do not proceed on the current live ISO until integration is reviewed.

Select one theme manually:
```sh
sudo plymouth-set-default-theme selah-experience
# Or use selah-experience-static for no motion.
sudo mkinitcpio -P
```
Use this only if the test system uses mkinitcpio; keep its existing hooks.
Inspect successful rebuild output and the selected boot image before reboot.
Do not add microcode initrd lines, copytoram, archisodevice, or replace GRUB files.
The theme cannot make Plymouth available on systems where it is not enabled.

Rollback BEFORE package removal: restore the recorded prior theme/configuration,
rebuild with the same initramfs tool, and verify a boot. If graphics or credentials
fail, use the retained working entry or recovery environment and restore the
backed-up configuration/images. Escape normally reveals Plymouth details.

## SDDM: preview before selection

Requires SDDM 0.21+ Qt 6 greeter, qt6-declarative and qt6-svg.
```sh
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/selah-experience
```
Close the preview when finished. It cannot authenticate or power off the machine.
The scaffold retains selectable installed sessions and keyboard layouts.

For VM activation, back up /etc/sddm.conf and /etc/sddm.conf.d first. Inspect ALL
[Theme] Current entries. /etc/sddm.conf overrides files in sddm.conf.d, so adding
a drop-in alone may not select this theme (the current profile sets Current in
both places). Change only the effective [Theme] Current value to
`selah-experience`. Preserve autologin, session and all other values.
Log out only after saving work; never restart SDDM in a live working session.

Rollback: restore the exact previous Current value/configuration before removing
the package. Existing profile uses `selahos`. Keep a working TTY accessible.

## Plasma: a throwaway user first

The package is discovered by System Settings → Colors & Themes → Global Theme.
Record the current theme AND color scheme (a theme may not restore an individually
customized scheme). Select Selah Experience (foundation) and only its color
component; do not request desktop layout replacement. The package supplies no
layouts, custom lock screen, shell or compositor. Existing Plasma fallback
components remain in use.

Rollback by selecting the recorded theme and color scheme before uninstall.
Do not modify another user's ~/.config files from a running desktop session.

## Remove

After restoring each active component and rebuilding any changed initramfs:
```sh
sudo pacman -R selah-experience
```
Do not use recursive dependency removal for this data package. Verify the next
boot/login. No background service or migration needs cleaning up.

## Integration is a later release decision

This branch changes only selah-experience/. Do not merge new package selection
into packages.x86_64 or copy payload into airootfs until the test matrix passes.
Beta 3 experiments are excluded entirely.
