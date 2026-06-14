#!/bin/bash
# Boot Windows VM with MPK mini IV USB passthrough.
# Run AFTER: bash install_windows.sh (Windows must be installed)
#
# The host usbmon still captures ALL USB traffic even while the device
# is passed through to the VM — that's how we get the activation packet.
#
# Run in parallel with capture_hid_vm.sh:
#   Terminal 1: bash capture_hid_vm.sh
#   Terminal 2: bash run_vm.sh
set -e
cd "$(dirname "$0")"

DISK="$(pwd)/windows.qcow2"
[ -f "$DISK" ] || { echo "Disk not found. Run install_windows.sh first."; exit 1; }

OVMF=""
for p in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd; do
    [ -f "$p" ] && OVMF="$p" && break
done
[ -z "$OVMF" ] && { echo "OVMF not found. sudo pacman -S edk2-ovmf"; exit 1; }

OVMF_VARS="$(pwd)/OVMF_VARS.fd"
[ -f "$OVMF_VARS" ] || { echo "OVMF_VARS.fd not found. Run install_windows.sh first."; exit 1; }

# Detect MPK mini IV USB bus/device
MPK_INFO=$(lsusb -d 09e8:005d 2>/dev/null | head -1)
if [ -z "$MPK_INFO" ]; then
    echo "ERROR: MPK mini IV (09e8:005d) not found. Plug it in first."
    exit 1
fi
echo "Found: $MPK_INFO"

# Unbind from host kernel drivers so QEMU can claim it
echo "Releasing MPK mini IV from host kernel..."
MPK_SYS=$(find /sys/bus/usb/devices -name "idVendor" -exec grep -l "09e8" {} \; 2>/dev/null | \
          xargs -I{} dirname {} | while read d; do
              [ "$(cat $d/idProduct 2>/dev/null)" = "005d" ] && echo "$d" && break
          done)

if [ -n "$MPK_SYS" ]; then
    DEVPATH=$(basename "$MPK_SYS")
    echo "  USB device: $DEVPATH"
    # Unbind MIDI driver so QEMU can claim the whole device
    for iface in "$MPK_SYS"/"$DEVPATH":*; do
        DRIVER=$(basename "$(readlink "$iface/driver" 2>/dev/null)" 2>/dev/null)
        if [ -n "$DRIVER" ] && [ "$DRIVER" != "usbhid" ]; then
            echo "  Unbinding interface $iface from $DRIVER..."
            echo "$DEVPATH:$(basename $iface | sed "s/${DEVPATH}://")" | \
                sudo tee /sys/bus/usb/drivers/"$DRIVER"/unbind 2>/dev/null || true
        fi
    done
fi

echo ""
echo "Starting Windows VM with MPK mini IV USB passthrough..."
echo "  IMPORTANT: In Windows, install the Akai editor then launch it."
echo "  Watch Terminal 1 (capture_hid_vm.sh) for the activation packet."
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
    -device e1000,netdev=net0 \
    -netdev user,id=net0 \
    -device qemu-xhci,id=xhci \
    -device usb-tablet \
    -device usb-host,vendorid=0x09e8,productid=0x005d \
    -vga std \
    -display sdl \
    -name "Windows VM - MPK mini IV Capture"
