# Windows VM for MPK mini IV HID Capture

Goal: Run the Akai MPK mini IV Editor in Windows, while Linux host captures
all USB traffic with usbmon → gets the HID activation packet.

## Step 1 — Get Windows ISO
Go to microsoft.com → Software Download → Windows 11
Download the "Windows 11 Disk Image (ISO) for x64 devices" (~6 GB).
Save to ~/Downloads/Win11.iso

If you prefer Windows 10 (no TPM requirement, smaller):
Download "Windows 10" ISO from the same site.

## Step 2 — Create VM disk
  cd ~/SelahOS-Dev/tools/mpk-mini-iv/vm
  bash create_vm_disk.sh

## Step 3 — Install Windows (first boot)
  bash install_windows.sh ~/Downloads/Win11.iso
  (Installs to the VM disk. Takes 20-40 min.)
  
  During install: choose "I don't have a product key", select Windows 11 Pro,
  use Custom install, select the virtual disk. Skip the network setup screen:
    → Shift+F10 → type: oobe\BypassNRO → Enter  (skips Microsoft account requirement)

## Step 4 — Start normal VM + start usbmon capture
  # Terminal 1 - usbmon capture:
  bash ../capture_hid_init_usb.sh
  
  # Terminal 2 - boot VM with USB passthrough:
  bash run_vm.sh

## Step 5 — Inside Windows VM
  1. Install the Akai MPK mini IV Editor (from the inMusic Software Center)
  2. Run the editor
  3. Watch Terminal 1 for the HID activation packet output

## Step 6 — Add activation packet to Python editor
  bash ../replay_hid_init.py ../hid_captures.txt
