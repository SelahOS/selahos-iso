#!/bin/bash
# Boot VM from Windows ISO to install Windows onto the VM disk.
# Usage: bash install_windows.sh ~/Downloads/Win11.iso
set -e
cd "$(dirname "$0")"

ISO="${1:-}"
if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: bash install_windows.sh /path/to/Windows.iso"
    echo ""
    echo "Windows 11 ISO: microsoft.com → Software Download → Windows 11"
    exit 1
fi

DISK="$(pwd)/windows.qcow2"
if [ ! -f "$DISK" ]; then
    echo "Disk not found. Run: bash create_vm_disk.sh"
    exit 1
fi

# Find OVMF firmware (Arch uses .4m.fd suffix)
OVMF=""
for p in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd; do
    [ -f "$p" ] && OVMF="$p" && break
done

if [ -z "$OVMF" ]; then
    echo "OVMF not found. Install: sudo pacman -S edk2-ovmf"
    exit 1
fi
echo "OVMF: $OVMF"

# Copy OVMF vars (writable — stores boot settings)
OVMF_VARS="$(pwd)/OVMF_VARS.fd"
OVMF_VARS_SRC="${OVMF/CODE/VARS}"
[ -f "$OVMF_VARS_SRC" ] && cp "$OVMF_VARS_SRC" "$OVMF_VARS" || cp "$OVMF" "$OVMF_VARS"

echo ""
echo "Launching Windows installer VM..."
echo "  ISO: $ISO"
echo "  Disk: $DISK"
echo "  RAM: 4GB  CPUs: 4"
echo ""
echo "TIPS:"
echo "  • Skip product key → Windows 11 Pro → Custom install → select the disk"
echo "  • No internet needed: Shift+F10 → oobe\\BypassNRO → Enter (skips MS account)"
echo "  • After install completes and you see the desktop, shut down the VM."
echo "  • Then run: bash run_vm.sh"
echo ""

qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,smm=on \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -m 2G \
    -smp 2,sockets=1,cores=2,threads=1 \
    -cpu host \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -device ich9-ahci,id=ahci \
    -drive file="$DISK",if=none,id=disk0,cache=writeback \
    -device ide-hd,drive=disk0,bus=ahci.0 \
    -drive file="$ISO",media=cdrom,readonly=on,if=none,id=cdrom0 \
    -device ide-cd,drive=cdrom0,bus=ahci.1,bootindex=1 \
    -device e1000,netdev=net0 \
    -netdev user,id=net0 \
    -device qemu-xhci \
    -device usb-tablet \
    -vga std \
    -display sdl \
    -boot order=d \
    -name "Windows VM - Install"
