#!/bin/bash
set -e
cd "$(dirname "$0")"

DISK=windows.qcow2
SIZE=60G

if [ -f "$DISK" ]; then
    echo "Disk $DISK already exists ($(du -sh $DISK | cut -f1)). Delete it first if you want to start over."
    exit 0
fi

echo "Creating $SIZE VM disk..."
qemu-img create -f qcow2 "$DISK" "$SIZE"
echo "Done: $DISK"
