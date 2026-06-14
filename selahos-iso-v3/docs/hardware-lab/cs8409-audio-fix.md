# CS8409 Audio Fix — CONFIRMED June 14 2026
## NEVER REMOVE THIS

## Solution
```bash
cd /tmp
git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro
sudo ./install.cirrus.driver.sh
```
Then FULL COLD SHUTDOWN. Cold boot = audio works.

## GRUB params required
acpi_osi=Darwin acpi_mask_gpe=0x57 pcie_aspm=off mem_sleep_default=deep

## Confirmed
MacBook Pro 14,1 / linux-zen 7.0.9 / June 14 2026 ✅
DO NOT USE AUR package — use GitHub source only
