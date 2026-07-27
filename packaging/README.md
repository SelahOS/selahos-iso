# SelahOS Packaging — OTA groundwork

Pacman packages for the SelahOS payload. This replaces the "loose files
copied from airootfs" model: pacman owns file lists and permissions
(permanently killing the SELAH-40/42/43 bug class), and versioned
packages are what `selah-update` will pull over the air from
`repo.selahos.io`.

## Packages

| Package | Contents |
|---|---|
| `selah-apps` | SelahBridgePro GUI + selahpro CLI, selahauth, selahwine, MPC bridge/led/snoop, MPK Mini IV, ASIO config, DAW profiles, app-compat DB, per-user selah-mpc-bridge service |
| `selah-device-editors` | device-bridge editor suite (APC Mini, LPD8 mk2/mk3, MPC Studio 2, MPD226, MPK261, dashboard) + launchers |
| `selah-theme` | Kvantum/Plasma/SDDM themes, selahos icon theme, wallpapers, color scheme, Konsole profile, fastfetch branding, /etc/skel defaults |
| `selah-tools` | selah-repair, selah-recover/rescue, selah-update (OTA wrapper), per-chip Wi-Fi driver selection (SELAH-41), recovery center, hardware DBs, seedcore service |

Live-ISO-only components (`selah-setup` installer, welcome/first-run,
calamares launcher) are intentionally NOT packaged — they stay in
airootfs.

## Building

```
bash ~/SelahOS-Dev/packaging/build-all.sh
```

Builds all four packages and assembles a local pacman repo in
`packaging/repo/` (`selahos.db`). Test on any machine with:

```
[selahos]
SigLevel = Never
Server = file:///home/dbnoble/SelahOS-Dev/packaging/repo
```

## Design decisions

- **Source of truth stays `selahos-iso-v3/airootfs/`** — PKGBUILDs read
  from it directly (`$startdir/../../…`). Nothing is duplicated; edit
  the airootfs file, rebuild the package.
- **`/usr/local` layout preserved for 1.0.x** — every desktop Exec
  line, script, and selah-repair path assumes it. Migrating to
  `/usr/bin` (Arch convention) is a coordinated rename for a later
  release, not a packaging-time change.
- **`/etc/selahbridgepro/.keydata` is NEVER packaged** — the license
  secret would otherwise ship world-downloadable in a repo. It remains
  an ISO-build-time deployment. Same for `license`/`trial.conf`.
- **`arch=('any')`** — everything is Python/Bash, no compiled bits.

## Adopting packages on systems installed the old way

Old installs already have these files as loose (pacman-untracked)
copies, so the first `pacman -S selah-apps …` will report file
conflicts. First adoption needs:

```
sudo pacman -S --overwrite '/usr/local/*,/etc/selahbridgepro/*,/etc/selah-mpc/*,/etc/xdg/fastfetch/*,/etc/skel/*' selah-apps selah-device-editors selah-theme selah-tools
```

(`selah-update` should wrap this for the migration release.)

## Roadmap to OTA (see project notes)

1. ✅ PKGBUILDs + local repo (this directory)
2. Stand up `repo.selahos.io` on web-core, sign packages
   (`repo-add --sign`), add `[selahos]` to the ISO's pacman.conf
3. Pin Arch packages per release via Arch Linux Archive snapshots
   (`archive.archlinux.org/repos/YYYY/MM/DD/`) + channel promotion
   in `selah-update` (beta → stable)
4. mkarchiso can then install these packages via `packages.x86_64`
   instead of airootfs loose files; selah-setup Step 10 shrinks to
   nearly nothing
5. btrfs + snapper rollback for new installs
