# MacBook10,1 Wi-Fi: association hangs indefinitely (open)

## Symptom
Fresh Beta 2.0.1 install, first-ever association attempt (no sleep/
resume involved): `nmcli device status` shows `wlp2s0 wifi connecting
(configuring)` stuck indefinitely; `ip link` shows `NO-CARRIER`/`state
DOWN`. This is a different bug from SELAH-51 (Wi-Fi not surviving sleep,
see that doc) — this one happens on the very first connection attempt.

## Root cause found (2026-09-12, live `journalctl -k` on real hardware)
```
brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac4350c2-pcie for chip BCM4350/5
brcmfmac 0000:02:00.0: Direct firmware load for brcm/brcmfmac4350c2-pcie.Apple Inc.-MacBook10,1.bin failed with error -2
brcmfmac 0000:02:00.0: Direct firmware load for brcm/brcmfmac4350c2-pcie.txt failed with error -2
brcmfmac 0000:02:00.0: Direct firmware load for brcm/brcmfmac4350c2-pcie.clm_blob failed with error -2
brcmfmac 0000:02:00.0: Direct firmware load for brcm/brcmfmac4350c2-pcie.txcap_blob failed with error -2
brcmfmac: brcmf_c_process_clm_blob: no clm_blob available (err=-2), device may have limited channels available
brcmfmac: brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)
```
`/lib/firmware/brcm/` (linux-firmware 20260810-2) only ships the generic
`brcmfmac4350-pcie.bin.zst` / `brcmfmac4350c2-pcie.bin.zst` firmware
blobs — no board-specific NVRAM `.txt`, `.clm_blob`, or `.txcap_blob` for
this exact board (PCI subsystem ID confirmed via `lspci -k`: `Apple Inc.
Device 0131`).

## Important nuance — don't over-attribute the hang to this alone
Upstream kernel history (`brcmfmac: Make sure CLM downloading is
optional`) confirms a missing CLM blob is treated as **non-fatal** — the
chip falls back to its own OTP-baked calibration with a restricted
channel set, logged as a warning, not a hard failure. So the missing
file is real and worth fixing, but it probably isn't the *entire*
mechanism behind an indefinite hang (a clean failure would be more
consistent with "no clm_blob, that's it"). A restricted/wrong channel
set is a plausible secondary factor — e.g. if the target AP is 5GHz-only
or on a channel excluded by the fallback set, association could stall
rather than fail cleanly.

## What was NOT done, on purpose
No fabricated NVRAM/CLM file was created or shipped. Apple's per-board
RF calibration data is proprietary and unpublished for this exact
board/antenna SKU as far as could be found (checked 2026-09-12); wrong
calibration data is worse than none — it can violate regulatory limits
or simply not work, and there's no way to verify correctness without lab
equipment. Don't ship a guessed file here.

## What WAS shipped as a try (2026-09-12)
`tools/hardware-lab/wifi_calibration_probe.sh` — sets an explicit
regulatory domain (commonly cited as the practical fix for "no clm_blob"
symptoms on Arch/Manjaro forums) and captures a full kernel +
NetworkManager log of the next connection attempt, so if the reg-domain
set alone doesn't fix it, the next session has real evidence instead of
more guessing. Safe and fully reversible — doesn't touch firmware files.

## Leads not yet followed up
- Recent upstream kernel work ("brcmfmac: pcie: Perform firmware
  selection for Apple platforms") suggests newer brcmfmac can read
  Apple's own calibration data directly from EFI NVRAM on real Apple
  hardware, independent of any linux-firmware file — worth checking
  whether `7.0.9-zen1-1-zen` actually has this merged, and whether
  `/sys/firmware/efi/efivars/` exposes anything usable on this machine,
  before spending more effort hunting for a static file.
- Test whether the hang is specific to 5GHz networks (try associating to
  a known 2.4GHz-only AP as an isolation test).
