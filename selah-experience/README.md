# Selah Experience Layer — Beta 2.0.2 foundation

Opt-in Plymouth theme, Qt 6 SDDM scaffold, Plasma 6 Look-and-Feel scaffold,
design tokens, and scene placeholders. This is a source foundation, not a
release-qualified replacement for the shipping boot/login experience.

- Source: `SelahOS/selahos-iso`, isolated branch `codex/selah-experience-beta2`.
- Worktree: `/home/dbnoble/Development/selahos`.
- Existing ISO profile, installer, boot loader, initramfs hooks, and desktop
  layouts are untouched. Nothing in this directory auto-activates a theme.
- Package identifiers are new: `selah-experience`, `selah-experience-static`
  (Plymouth), `selah-experience` (SDDM), `org.selah.desktop` (Plasma).
- Reuse recorded Selah branding; no replacement logo or Plasma fork.

Read [assumptions](docs/ASSUMPTIONS.md), [install/rollback](docs/INSTALL.md),
[test gates](docs/TESTING.md), and [validation results](docs/VALIDATION.md).
Beta 3 ideas are explicitly excluded from the package; see
[experiments](experiments/beta3/README.md).

## Source map

`design/` holds tokens and budgets; `branding/` holds the unmodified source
logo and provenance; `boot/`, `login/`, `plasma/` hold runtime themes;
`scenes/` contains deliberately simple static SVG placeholders;
`tools/` contains generation and verification tools; `packaging/` builds
an Arch package. No service, network request, telemetry, video, or audio loop.

## Build

On the development machine, from this directory:

```sh
python3 tools/check.py
cd packaging
makepkg
```

Build does not install or activate anything. See INSTALL.md before any activation.
