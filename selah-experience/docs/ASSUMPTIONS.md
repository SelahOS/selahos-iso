# Repository and assumptions — 2026-09-16

Approved implementation repository: SelahOS/selahos-iso. Isolated worktree
`/home/dbnoble/Development/selahos` derives from local commit
`2d49905` at `/home/dbnoble/SelahOS-Dev`. At inspection, its working
tree was clean and main was 22 commits ahead of its locally recorded origin/main;
no fetch, pull, rebase, push or merge was performed.

The build wrapper `/home/dbnoble/selah-build.sh` points to
`/home/dbnoble/SelahOS-Dev/selahos-iso-v3/`. It deletes build/output directories
when run; it was read, NOT executed. The older
`/home/dbnoble/selahos-iso-build` has modified/untracked boot and installer
files and was not imported or changed. The nested `selahos-website` checkout
uses SelahOS/selahos for the website/backend; it is not the ISO source tree.
SelahTrade is unrelated and untouched.

Current live ISO mkinitcpio hooks do NOT include Plymouth. Installing this
package alone therefore does not produce a splash on that ISO. Do not add hooks
or change GRUB merely to demo the artwork. First qualify it on a disposable
Plymouth-enabled Arch/Plasma VM with a known working boot baseline.

Existing source Plymouth script refers to logo.png while this source asset
directory contains selah-logo.png and logo.svg. This work does not repair or
activate that older theme. New assets use an explicit generated logo.png from
the existing logo.svg, with provenance.

Runtime targets available on the dev host: Plymouth 26.134.222-2, SDDM 0.21.0-7,
Plasma workspace 6.7.4-3, Qt 6.11.2. These are newer than the original Beta
2.0.2 target may have used; compatibility with the release ISO must be verified.
No Plasma Login Manager migration. No custom lock screen, panel layout,
compositor, global shortcut, PAM, autologin or installer changes.
