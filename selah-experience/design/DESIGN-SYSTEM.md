# Design system

Pause → Reflect → Create: quiet space, bounded resonance, then the existing Selah
mark. Gold (#D6A85A, #E6C27A, #BD8B3C), navy charcoal (#0D1020, #171C2A,
#2A3042), white and error terracotta come from the existing SDDM/theme assets.
Muted text #B8BDC9 is a new supporting token for readable secondary labels.

`tokens.json` is the source of truth. `tools/generate.py` generates the QML
token object and Plymouth assets/settings. Commit generated outputs so runtime
requires neither Python nor asset generators. Use `--check` to detect drift.
Body text is 16px Noto Sans, with system sans fallback; no bundled web fonts.
Spacing follows 4/8/12/16/24/32/48px. Minimum interactive height is 44px.
Rounded inputs use 8px; buttons 10px. Focus uses a 2px gold outline.

White and muted labels stay on dark surfaces; button text uses dark background
on gold. Accessible labels, visible focus, keyboard navigation, session and
keyboard-layout selection are part of the login scaffold. Passwords never
appear in logs or error strings. Production accessibility and multi-display
testing remain release gates.
