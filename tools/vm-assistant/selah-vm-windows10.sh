#!/usr/bin/env bash
# Builds and launches a fully unattended Windows 10 test VM via libvirt/virt-install.
# Sibling to selah-vm-windows.sh (Windows 11) — kept as a separate script rather than
# a flag on that one since the two need different autounattend.xml files, ISO, and
# os-variant, and Windows 11 support is still unresolved (see the 08-28 resume log)
# while this one is confirmed working end to end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="${VM_NAME:-selah-win10-test}"
MEMORY_MB="${MEMORY_MB:-4096}"
VCPUS="${VCPUS:-4}"
DISK_GB="${DISK_GB:-64}"
BUILD_DIR="$HOME/vm-build/windows"
WIN_ISO="${WIN_ISO:-$HOME/Downloads/Win10_21H1_English_x64.iso}"
VIRTIO_ISO="$BUILD_DIR/virtio-win.iso"
AUTOUNATTEND_XML="$SCRIPT_DIR/autounattend-win10.xml"
AUTOUNATTEND_ISO="$BUILD_DIR/autounattend-win10.iso"

mkdir -p "$BUILD_DIR"

# Same disk-reuse gotcha as the Windows 11 script: if you `virsh undefine`
# without also deleting /var/lib/libvirt/images/$VM_NAME.qcow2 (root/
# libvirt-qemu-owned, needs sudo), a re-run reuses that file, and if it
# already has a completed install on it Setup shows an "upgrade vs. clean
# install" dialog this script's automation can't answer. Either `sudo rm`
# the old disk first, or point VM_NAME at a new name.

# Idempotency guard moved ahead of capability-check.sh (fixed 08-29):
# capability-check gates on free RAM for a NEW guest, which wrongly fails
# when checking status on a guest that's already running and holding its
# own memory — discovered when this exact ordering bug was first fixed in
# selah-vm-macos.sh's libvirt migration, then found here too.
if ! groups | grep -qw libvirt || ! groups | grep -qw kvm; then
  echo "ERROR: current shell is not in the libvirt/kvm groups yet." >&2
  echo "Run: sudo usermod -aG libvirt,kvm \$USER ; then start a new shell" >&2
  exit 1
fi
# The check above already guarantees libvirt+kvm are active in this shell,
# so the rest of this script calls virsh/virt-install directly rather than
# via sg/newgrp wrapping (08-31: sg is also just gone from this system now —
# the shadow package upgrade dropped it — so this sidesteps needing a
# newgrp-based replacement throughout, see selah-vm-macos.sh for the same fix).

if virsh --connect qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
  echo "VM '$VM_NAME' already exists. Current state:"
  virsh --connect qemu:///system domstate "$VM_NAME"
  exit 0
fi

bash "$SCRIPT_DIR/capability-check.sh" "$MEMORY_MB"

if [ ! -f "$WIN_ISO" ]; then
  echo "ERROR: no Windows 10 ISO found at $WIN_ISO" >&2
  echo "Set WIN_ISO=/path/to/your.iso, or place one at $WIN_ISO." >&2
  exit 1
fi
echo "Using existing Windows 10 ISO: $WIN_ISO"

if [ ! -f "$VIRTIO_ISO" ]; then
  echo "Fetching virtio-win driver ISO..."
  curl -L --max-time 600 -o "$VIRTIO_ISO" \
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
fi

echo "Building autounattend.iso..."
# -graft-points is required here (unlike the Windows 11 script): the source
# file isn't literally named autounattend.xml (this repo keeps both configs
# side by side), but Windows Setup only auto-detects that exact filename at
# the root of the ISO, so the graft point renames it on the way in.
xorriso -as mkisofs -o "$AUTOUNATTEND_ISO" -V "AUTOUNATTEND" -J -R \
  -graft-points /autounattend.xml="$AUTOUNATTEND_XML"

# libvirtd (qemu:///system) runs as libvirt-qemu and needs search permission
# to traverse $HOME to reach the ISOs; grant only +x on $HOME itself, nothing else.
if ! getfacl -p "$HOME" 2>/dev/null | grep -q '^user:libvirt-qemu:.*x'; then
  echo "Granting libvirt-qemu search access to $HOME..."
  setfacl -m u:libvirt-qemu:x "$HOME"
fi

virsh --connect qemu:///system net-list --all | grep -q "^ default .*active" || \
  { virsh --connect qemu:///system net-start default && virsh --connect qemu:///system net-autostart default; }

echo "Launching unattended Windows 10 install..."
# Confirmed working 08-28. The one real fix that made this succeed: a
# multi-edition retail ISO needs an actual product key value to resolve
# which edition to install, even with /IMAGE/INDEX also specified in
# autounattend-win10.xml — an empty <ProductKey><WillShowUI>Never</...>
# (no <Key>) fails identically to omitting the element entirely, with
# Setup blocking on "Windows cannot read the <ProductKey> setting from the
# unattend answer file." Fixed with Microsoft's public generic/KMS-client
# setup key for the target edition (Pro, matching index 6 in the XML) —
# this doesn't activate Windows, it only selects the edition and suppresses
# the key-entry prompt.
# TPM disabled and non-secure firmware aren't strictly required by Windows
# 10 (unlike 11), but kept for consistency with the working Win11 script and
# because this host's swtpm emulator was confirmed flaky under load — no
# reason to reintroduce that risk here.
virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --memory "$MEMORY_MB" --vcpus "$VCPUS" \
  --disk path=/var/lib/libvirt/images/$VM_NAME.qcow2,size=$DISK_GB,bus=sata \
  --cdrom "$WIN_ISO" \
  --disk "$VIRTIO_ISO",device=cdrom \
  --disk "$AUTOUNATTEND_ISO",device=cdrom \
  --os-variant win10 \
  --network network=default,model=virtio \
  --graphics vnc \
  --tpm none \
  --boot cdrom,hd,loader=/usr/share/edk2/x64/OVMF_CODE.4m.fd,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=/usr/share/edk2/x64/OVMF_VARS.4m.fd \
  --noautoconsole


# Microsoft's UEFI install media shows a "Press any key to boot from CD or
# DVD..." gate on every boot. With --noautoconsole nothing presses it, so the
# install silently falls through to "no bootable device" and never starts.
# Spam Enter for the first ~30s to reliably catch that window.
echo "Catching the UEFI 'press any key to boot from CD' prompt..."
for _ in $(seq 1 30); do
  virsh --connect qemu:///system send-key "$VM_NAME" --codeset linux KEY_ENTER >/dev/null 2>&1
  sleep 1
done

# POST-INSTALL PERFORMANCE NOTE (confirmed 08-28): the initial disk is created
# with bus=sata above (ide-hd emulation under the hood — slow). To convert to
# virtio-blk for real performance after Windows is installed and
# virtio-win-guest-tools.exe has been run inside the guest (installs the
# viostor driver package but does NOT register it as boot-critical, since no
# virtio disk existed for it to bind to at install time — running the
# installer alone is not sufficient):
#   1. While the VM is still running on the SATA disk, live-attach a small
#      throwaway virtio disk so Windows PnP-binds viostor for real and
#      populates the CriticalDeviceDatabase + boot-start service entries:
#        virsh vol-create-as default tmp-viotest.qcow2 1G --format qcow2
#        virsh attach-disk $VM_NAME /var/lib/libvirt/images/tmp-viotest.qcow2 \
#          vdz --targetbus virtio --subdriver qcow2 --live --config
#   2. Shut the VM down cleanly, detach+delete the throwaway disk:
#        virsh shutdown $VM_NAME   # wait for "shut off"
#        virsh detach-disk $VM_NAME vdz --config
#        virsh vol-delete tmp-viotest.qcow2 default
#   3. Edit the domain XML (virsh dumpxml > file, edit, virsh define file):
#      change the boot disk's <target dev='sda' bus='sata'/> to
#      <target dev='vda' bus='virtio'/> (drop the sata <address> line, PCI
#      addressing is auto-assigned), and add a QEMU guest agent channel:
#      <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
#   Skipping step 1 and converting the disk directly reliably produces a
#   BSOD 0x7B INACCESSIBLE_BOOT_DEVICE on next boot (confirmed) — it is
#   recoverable (just revert dev/bus back to sda/sata and redefine, no data
#   loss), but step 1 avoids it entirely and is the correct fix.

echo "Started. Poll with:"
echo "  virsh --connect qemu:///system domstate $VM_NAME"
echo "  virsh --connect qemu:///system domifaddr $VM_NAME"
echo ""
echo "Once Setup reaches ~96%/'Requesting reboot of system...' and the domain"
echo "goes to 'shut off', do NOT undefine/rebuild — just:"
echo "  virsh --connect qemu:///system start $VM_NAME"
echo "libvirt/OVMF turns that guest reboot into a full shutdown (not yet"
echo "understood why) but the disk+NVRAM state is fine; undefining forces a"
echo "full fresh reinstall via WillWipeDisk=true and looks like a false"
echo "dead-end. Login once booted: selah / SelahTest!2026"
