# CS4208 internal speaker: GPIO investigation (open, unresolved)

## Summary
Two independent driver forks (`leifliddy/macbook12-audio-driver`,
investigated 2026-08-13; `juicecultus/macbook12-audio-driver`, shipped in
Beta 2.0.1, tested 2026-09-12) both correctly identify the codec, wire up
a legitimate `Fixed Speaker at Int` pin, and drive `GPIO0` (the presumed
amp-enable line) high — and both leave the internal speaker completely
silent on the same physical MacBook10,1 test unit. Headphones work fine
through this unit, isolating the fault to the internal-speaker digital
link + GPIO-amp path specifically.

## What's been ruled out (with hard evidence, both sessions)
- Stream lifecycle (PCM open/prepare/close) — clean, no premature close.
- ALSA/PipeWire mute or zero volume — Master/PCM/Speaker sink all
  unmuted, 100%/1.00.
- Speaker pin disabled — `Pin-ctls: 0x40: OUT`, correctly enabled.
- DAC power state mid-playback — `D0`, correctly on.
- GPIO0 asserted — `dir=1, data=1`, matches the driver's own intent, in
  both forks, at rest and mid-playback.
- Driver logic vs upstream — byte-identical to the actively-maintained
  leifliddy repo as of August; juicecultus fork independently arrives at
  the same GPIO end state via a different code path (unconditional
  `setup_a1534()` instead of an SSID-matched table).
- A known similar upstream issue (leifliddy/macbook12-audio-driver#27) —
  looked similar but is a different mechanism that doesn't apply here.

## What hasn't been tried
GPIO4 and GPIO5 are configured as outputs (`SET_GPIO_DIRECTION` sets bits
0, 4, 5) but only bit 0 is ever driven high across either driver's
source — this looks deliberate/state-machine-like, not arbitrary, but
it's a real gap: nobody has tried driving 4/5 instead of (or in addition
to) 0, or trying bit 0 LOW instead of high (an inverted-polarity guess).
`tools/hardware-lab/gpio_poke.py` exists to try these live, in seconds,
without a rebuild/reboot cycle per guess — see that script's docstring
for the exact values to try and why.

## Known blocker
Raw `/dev/snd/hwC0D0` access (needed for the poke script) is blocked by
a systemd device-cgroup policy when reached over SSH, even with correct
Unix permissions/ACLs — must run from a terminal inside the actual local
desktop session on the target machine.

## If GPIO poking finds nothing
Equally plausible at this point as a wrong GPIO guess: a genuine physical
fault in this specific test unit (loose/damaged internal speaker or amp
chip). Worth physically opening the machine and checking the speaker
connector/cable seating before spending more time on software guesses.
