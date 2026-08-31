#!/usr/bin/env bash
# Builds and launches a fully unattended Windows test VM via libvirt/virt-install.
# Reuses an existing Win11.iso if present in ~/Downloads instead of re-fetching one,
# since Microsoft's download links are session-signed and not stable to hardcode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="${VM_NAME:-selah-win11-test}"
MEMORY_MB="${MEMORY_MB:-8192}"
VCPUS="${VCPUS:-4}"
DISK_GB="${DISK_GB:-64}"
BUILD_DIR="$HOME/vm-build/windows"
WIN_ISO="${WIN_ISO:-$HOME/Downloads/Win11.iso}"
VIRTIO_ISO="$BUILD_DIR/virtio-win.iso"
AUTOUNATTEND_XML="$SCRIPT_DIR/autounattend.xml"
AUTOUNATTEND_ISO="$BUILD_DIR/autounattend.iso"

mkdir -p "$BUILD_DIR"

# NOTE: if you `virsh undefine` this domain between runs without also
# deleting /var/lib/libvirt/images/$VM_NAME.qcow2 (the disk is root/
# libvirt-qemu-owned, needs sudo), a re-run reuses that file. If it already
# has a completed Windows install on it, Setup shows an "upgrade vs. clean
# install" dialog that this script's automation can't answer (blocks
# forever). Either `sudo rm` the old disk first, or point VM_NAME at a new
# name so a fresh disk gets allocated.

bash "$SCRIPT_DIR/capability-check.sh" "$MEMORY_MB"

if [ ! -f "$WIN_ISO" ]; then
  echo "ERROR: no Windows ISO found at $WIN_ISO" >&2
  echo "Fetch one from https://www.microsoft.com/software-download/windows11 using a non-Windows User-Agent to get a signed link, then re-run." >&2
  exit 1
fi
echo "Using existing Windows ISO: $WIN_ISO"

if [ ! -f "$VIRTIO_ISO" ]; then
  echo "Fetching virtio-win driver ISO..."
  curl -L --max-time 600 -o "$VIRTIO_ISO" \
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
fi

echo "Building autounattend.iso..."
xorriso -as mkisofs -o "$AUTOUNATTEND_ISO" -V "AUTOUNATTEND" -J -R "$AUTOUNATTEND_XML"

# libvirtd (qemu:///system) runs as libvirt-qemu and needs search permission
# to traverse $HOME to reach the ISOs; grant only +x on $HOME itself, nothing else.
if ! getfacl -p "$HOME" 2>/dev/null | grep -q '^user:libvirt-qemu:.*x'; then
  echo "Granting libvirt-qemu search access to $HOME..."
  setfacl -m u:libvirt-qemu:x "$HOME"
fi

if ! groups | grep -qw libvirt || ! groups | grep -qw kvm; then
  echo "ERROR: current shell is not in the libvirt/kvm groups yet." >&2
  echo "Run: sudo usermod -aG libvirt,kvm \$USER ; then start a new shell (or use sg libvirt -c 'sg kvm -c \"...\"')" >&2
  exit 1
fi

sg libvirt -c "sg kvm -c 'virsh --connect qemu:///system net-list --all'" | grep -q "^ default .*active" || \
  sg libvirt -c "sg kvm -c 'virsh --connect qemu:///system net-start default && virsh --connect qemu:///system net-autostart default'"

if sg libvirt -c "sg kvm -c 'virsh --connect qemu:///system dominfo $VM_NAME'" >/dev/null 2>&1; then
  echo "VM '$VM_NAME' already exists. Current state:"
  sg libvirt -c "sg kvm -c 'virsh --connect qemu:///system domstate $VM_NAME'"
  exit 0
fi

echo "Launching unattended Windows install..."
# Root cause of the recurring, seemingly-random "computer restarted
# unexpectedly" crashes (reproduced identically across virtio-blk,
# virtio-scsi, and SATA disk backends, and across secure/non-secure OVMF) is
# this host's swtpm (vTPM emulator) becoming unreliable, confirmed by direct
# A/B test: identical launch with `--tpm none` survived every point where
# TPM-enabled launches died (crash timing varied 6-24s, inconsistent with a
# fixed timeout, consistent with a swtpm-internal race). We don't yet know
# *why* swtpm on this host is flaky. Disabling TPM plus the LabConfig
# registry bypass below (so Setup's hardware check doesn't just block
# instead, since Windows 11 normally requires TPM 2.0) sidesteps it
# entirely.
# --boot forces cdrom-then-hd order explicitly: reusing an existing disk that
# already has a working Windows Boot Manager on it (from a prior attempt)
# while switching firmware/loader made the firmware boot straight into that
# stale install instead of the CD. Explicit order makes every launch
# CD-first regardless of what's already on the disk.
sg libvirt -c "sg kvm -c '
virt-install \
  --connect qemu:///system \
  --name $VM_NAME \
  --memory $MEMORY_MB --vcpus $VCPUS \
  --disk path=/var/lib/libvirt/images/$VM_NAME.qcow2,size=$DISK_GB,bus=sata \
  --cdrom $WIN_ISO \
  --disk $VIRTIO_ISO,device=cdrom \
  --disk $AUTOUNATTEND_ISO,device=cdrom \
  --os-variant win11 \
  --network network=default,model=virtio \
  --graphics vnc \
  --tpm none \
  --boot cdrom,hd,loader=/usr/share/edk2/x64/OVMF_CODE.4m.fd,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=/usr/share/edk2/x64/OVMF_VARS.4m.fd \
  --noautoconsole
'"


# Microsoft's UEFI install media shows a "Press any key to boot from CD or
# DVD..." gate on every boot. With --noautoconsole nothing presses it, so the
# install silently falls through to "no bootable device" and never starts.
# Spam Enter for the first ~30s to reliably catch that window.
echo "Catching the UEFI 'press any key to boot from CD' prompt..."
for _ in $(seq 1 30); do
  sg libvirt -c "sg kvm -c 'virsh --connect qemu:///system send-key $VM_NAME --codeset linux KEY_ENTER'" >/dev/null 2>&1
  sleep 1
done

echo "Started. Poll with:"
echo "  virsh --connect qemu:///system domstate $VM_NAME"
echo "  virsh --connect qemu:///system domifaddr $VM_NAME"
