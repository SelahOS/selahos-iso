# CS4208 Audio Fix — CONFIRMED September 6 2026
## NEVER REMOVE THIS

## Root cause
Stock kernel `snd-hda-codec-cs420x` picks a **blank** pin fixup for this
codec's subsystem ID (`106b:6600` — not present in the upstream fixup
table), so autoconfig never wires the internal speaker at all
(`speaker_outs=0` in dmesg). Not a PipeWire/ALSA config issue — no
software-level errors, just an unwired output.

## Solution
```bash
git clone https://github.com/juicecultus/macbook12-audio-driver.git
cd macbook12-audio-driver
sudo bash install.cirrus.driver.sh -i
```
Then a clean reboot (live hot-unload of the stock module fails —
`snd_hda_codec_generic` stays in use — don't fight it, just reboot).

## Confirmed
MacBook10,1 (2017 12" MacBook) / linux-zen 7.0.9 / September 6 2026 ✅
- Module loads: `snd_hda_codec_cs420x` from
  `/usr/lib/modules/<ver>/updates/dkms/snd-hda-codec-cs420x.ko.zst`
- `cs4208_probe()` in this fork's patched `cs420x.c` runs
  `setup_a1534()`/`play_a1534()` **unconditionally** for every CS4208
  codec, regardless of SSID match — this is what actually fixes the
  hardware; the vendor's own `cs4208_mac_fixup_tbl` doesn't have an entry
  for this SSID and isn't what does the work.
- Direct ALSA playback test (`speaker-test -D hw:0,0 -r 44100`) opens
  cleanly with correct period timing and no errors. **44100Hz is the
  ONLY rate the device exposes post-fix** (`RATE: 44100`, not a range) —
  this is the codec's native DSP rate, not a bug. 48000Hz correctly
  fails to open.
- Real audible sound not yet confirmed by a human ear (SSH-only access
  overnight) — software-level signal is as strong as it gets remotely.

## Packaged as
`packaging/snd-hda-macbook12-dkms-git/` (same structure as the CS8409
sibling package `snd-hda-macbookpro-dkms-git`). Baked into the live ISO
at build time via `customize_airootfs.sh` Step 18b (network available
during ISO build, not during an offline install) — see that file for the
exact mechanism. Also listed in `selahos-install-packages/base.txt` so it
pacstraps onto installed systems too.

## Open follow-up
Same as the CS8409 sibling: this package's `dkms.conf` `PRE_BUILD` step
downloads the matching kernel source tarball from `cdn.kernel.org` at
build time. Baking it into the live ISO (Step 18b) sidesteps needing
network at *install* time, but relies on the live ISO's kernel version
exactly matching what pacstrap installs onto the target — true today
(same `linux-zen` package, same offline repo), but worth re-checking if
the kernel package ever gets bumped without rebuilding this driver too.
