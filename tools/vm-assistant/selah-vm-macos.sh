#!/usr/bin/env bash
# Fetches a macOS recovery image via OSX-KVM's own fetch-macOS-v2.py (which
# already encodes the correct board-id per version, and verifies the download
# against Apple's own chunklist hashes internally — no separate checksum step
# needed here), then defines and starts it as a libvirt domain (matching how
# selah-vm-windows10.sh manages Windows) instead of a raw unmanaged QEMU
# process. Migrated 08-28/08-29 after the raw-process version silently died
# on a host reboot with no way to tell it wasn't just hidden — a libvirt
# domain definition persists in /etc/libvirt/qemu/*.xml independent of any
# running process, so `virsh start` after a reboot just works.
#
# The original raw-QEMU version is kept at selah-vm-macos-raw.sh.bak as a
# rollback fallback until this version has more mileage on it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-}"
VERSIONS_CONF="$SCRIPT_DIR/macos-versions.conf"
DOMAIN_TEMPLATE="$SCRIPT_DIR/macos-libvirt-domain.xml.template"
OSX_KVM_DIR="${OSX_KVM_DIR:-$HOME/vm-build/OSX-KVM}"
# 4096 (not the previous 8192 default) matches what's actually proven to work
# on this host for a test/dev guest — this machine only has 7.6GB total RAM,
# of which the always-on Claude sandbox VM permanently holds 4GB. Apple's 8GB
# figure is the "recommended for daily use" number, not the install-time
# minimum.
MEMORY_MB="${MEMORY_MB:-4096}"
DISK_GB="${DISK_GB:-128}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  echo "Available versions:" >&2
  grep -v '^#' "$VERSIONS_CONF" | cut -d: -f1 | sed 's/^/  - /' >&2
  exit 1
fi

line=$(grep -v '^#' "$VERSIONS_CONF" | grep "^$VERSION:" || true)
if [ -z "$line" ]; then
  echo "ERROR: unknown version '$VERSION'. Available:" >&2
  grep -v '^#' "$VERSIONS_CONF" | cut -d: -f1 | sed 's/^/  - /' >&2
  exit 1
fi
FETCH_SHORTNAME=$(echo "$line" | cut -d: -f2)
CPU_MODEL=$(echo "$line" | cut -d: -f3)
VM_NAME="selah-macos-$VERSION"

# Per macos-versions.conf: Skylake-Client is used for Sonoma/Sequoia/Tahoe,
# which is also exactly the set that requires AVX2 on the host.
REQUIRED_CPU_FLAG=""
case "$CPU_MODEL" in
  Skylake-Client*) REQUIRED_CPU_FLAG="avx2" ;;
esac

if ! groups | grep -qw libvirt || ! groups | grep -qw kvm; then
  echo "ERROR: current shell is not in the libvirt/kvm groups yet." >&2
  echo "Run: sudo usermod -aG libvirt,kvm \$USER ; then start a new shell" >&2
  exit 1
fi
# The check above already guarantees libvirt+kvm are active in this shell,
# so the rest of this script calls virsh directly rather than via sg/newgrp
# wrapping — that wrapping was originally defensive for a stale-shell case
# this check already rules out. (08-31: sg itself is now gone from this
# system — the shadow package upgrade dropped it — so this simplification
# also sidesteps needing a newgrp-based replacement throughout.)

print_connection_info() {
  local ip display
  ip=$(virsh --connect qemu:///system domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1)
  # domdisplay (not vncdisplay) — works regardless of graphics protocol;
  # this domain uses SPICE (08-29, switched from VNC for interactive-use
  # responsiveness, matching OSX-KVM's own reference config).
  display=$(virsh --connect qemu:///system domdisplay "$VM_NAME" 2>/dev/null || true)
  echo "SSH (once network is up): ssh <user>@${ip:-<pending — retry: virsh domifaddr $VM_NAME>}"
  echo "Display: ${display:-<not available — domain may not be running>}"
  echo "Connect with: remote-viewer '$display'   (SPICE, not VNC — gvncviewer/krdc won't work here)"
  echo "QMP socket (for macos-qmp-helper.py / macos-install-automate.py): $WORK_DIR/qmp.sock"
  echo "  (connect via: echo '...' | newgrp libvirt-qemu — the running QEMU process owns this socket as user libvirt-qemu)"
}

WORK_DIR="$HOME/vm-build/macos-$VERSION"

# Idempotency guard: if the domain is already defined, don't rebuild — this
# is the actual fix for "the VM died on reboot and I can't find it": the
# domain definition persists independent of any running process, so just
# (re)start it if it's not already running.
if virsh --connect qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
  state=$(virsh --connect qemu:///system domstate "$VM_NAME")
  echo "VM '$VM_NAME' already defined. State: $state"
  if [ "$state" != "running" ]; then
    echo "Starting it..."
    virsh --connect qemu:///system start "$VM_NAME"
    # The QMP socket in qemu:commandline is a brand-new file each start —
    # dbnoble needs an ACL grant on WORK_DIR to let the libvirt-qemu-owned
    # QEMU process create it there (confirmed necessary on this host: without
    # it, QEMU fails to even start with "Failed to bind socket... Permission
    # denied", since the directory has no "other" write bit).
    setfacl -m u:libvirt-qemu:rwx "$WORK_DIR" 2>/dev/null || true
  fi
  print_connection_info
  exit 0
fi

# Everything below only runs for a genuinely new domain — capability-check
# gates on free RAM for a NEW guest, which is meaningless (and would wrongly
# fail) against a guest that's already running and holding its own memory,
# hence this sits after the idempotency guard above, not before it.
if [ ! -d "$OSX_KVM_DIR" ]; then
  echo "ERROR: OSX-KVM not found at $OSX_KVM_DIR. Clone it first:" >&2
  echo "  git clone https://github.com/kholia/OSX-KVM.git $OSX_KVM_DIR" >&2
  exit 1
fi

bash "$SCRIPT_DIR/capability-check.sh" "$MEMORY_MB" "$REQUIRED_CPU_FLAG"

if ! command -v dmg2img >/dev/null 2>&1; then
  echo "ERROR: dmg2img not found (AUR-only package). Install with: yay -S dmg2img" >&2
  exit 1
fi

virsh --connect qemu:///system net-list --all | grep -q "^ default .*active" || \
  { virsh --connect qemu:///system net-start default && virsh --connect qemu:///system net-autostart default; }

mkdir -p "$WORK_DIR" "$WORK_DIR/screenshots"
cd "$WORK_DIR"

if [ ! -f BaseSystem.img ]; then
  if [ ! -f BaseSystem.dmg ]; then
    echo "Fetching macOS $VERSION recovery image (shortname: $FETCH_SHORTNAME)..."
    # fetch-macOS-v2.py's progress bar calls os.get_terminal_size(), which
    # throws ENOTTY ("Inappropriate ioctl for device") once the download
    # finishes and it moves on to chunklist verification, if stdout isn't a
    # real terminal (e.g. redirected to a log file under nohup/background).
    # The download itself is unaffected — only the verification step's
    # progress rendering crashes — but that aborts before confirming
    # integrity, so wrap in `script` to allocate a pty and dodge it.
    if script -qec "python3 '$OSX_KVM_DIR/fetch-macOS-v2.py' -s '$FETCH_SHORTNAME' --action download -o '$WORK_DIR'" /dev/null; then
      echo "Fetch OK: BaseSystem.dmg (verified against Apple's chunklist hashes by fetch-macOS-v2.py itself)."
    else
      echo "ERROR: fetch-macOS-v2.py failed — see output above. Not proceeding to conversion with a missing/partial file." >&2
      exit 1
    fi
  fi
  echo "Converting BaseSystem.dmg -> BaseSystem.img..."
  if dmg2img -i BaseSystem.dmg BaseSystem.img; then
    echo "Convert OK: BaseSystem.img"
  else
    echo "ERROR: dmg2img failed. Removing partial BaseSystem.img so the next run retries cleanly." >&2
    rm -f BaseSystem.img
    exit 1
  fi
fi

if [ ! -f mac_hdd_ng.img ]; then
  echo "Creating target disk image (${DISK_GB}G)..."
  qemu-img create -f qcow2 mac_hdd_ng.img "${DISK_GB}G"
fi

if [ ! -f OpenCore.qcow2 ]; then
  cp "$OSX_KVM_DIR/OpenCore/OpenCore.qcow2" .
fi
for f in OVMF_CODE_4M.fd OVMF_VARS-1920x1080.fd; do
  [ -f "$f" ] || cp "$OSX_KVM_DIR/$f" .
done

# libvirt-qemu (the user QEMU actually runs as under libvirt) needs write
# access to WORK_DIR to create the qemu:commandline QMP socket at start time
# — confirmed necessary on this host (see comment above / RESUME notes).
setfacl -m u:libvirt-qemu:rwx "$WORK_DIR"

# NIC: vmxnet3, not e1000-82545em. Confirmed live on this host (Sequoia,
# 2026-08-28): e1000-82545em's PCI device attaches but no en0 ever appears —
# modern macOS (Sonoma/Sequoia/Tahoe) has dropped kernel support for that
# legacy Intel NIC emulation. vmxnet3 gets a real en0 and working internet.
# Unlike the raw-QEMU version's -netdev user,hostfwd=tcp::2222-:22, this NIC
# is attached to libvirt's default NAT network (matching the Windows VM's
# pattern) — SSH access is via `virsh domifaddr`, not a fixed host port.
MY_OPTIONS="+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"
MEMORY_KIB=$((MEMORY_MB * 1024))

DOMAIN_XML="$WORK_DIR/domain.xml"
sed \
  -e "s|__VM_NAME__|$VM_NAME|g" \
  -e "s|__MEMORY_KIB__|$MEMORY_KIB|g" \
  -e "s|__WORK_DIR__|$WORK_DIR|g" \
  -e "s|__CPU_MODEL__|$CPU_MODEL|g" \
  -e "s|__MY_OPTIONS__|$MY_OPTIONS|g" \
  "$DOMAIN_TEMPLATE" > "$DOMAIN_XML"

echo "Defining and starting macOS $VERSION under libvirt (domain: $VM_NAME)..."
virsh --connect qemu:///system define "$DOMAIN_XML"
virsh --connect qemu:///system start "$VM_NAME"

# Boot-verification gate: poll domain state instead of a blind sleep, same
# discipline used for the Windows virtio-blk boot check and the original
# raw-QEMU version of this script.
echo "Verifying boot (domain state == running)..."
BOOT_OK=0
for _ in $(seq 1 30); do
  state=$(virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null || echo "unknown")
  if [ "$state" = "running" ]; then
    BOOT_OK=1
    break
  fi
  if [ "$state" = "shut off" ] || [ "$state" = "crashed" ]; then
    echo "ERROR: domain entered state '$state' during startup." >&2
    exit 1
  fi
  sleep 2
done

if [ "$BOOT_OK" -ne 1 ]; then
  echo "ERROR: domain never reached 'running' within 60s. Check: virsh --connect qemu:///system domstate $VM_NAME" >&2
  exit 1
fi

echo "Boot verification OK: domain is running."
print_connection_info
echo ""
echo "Next: run macos-install-automate.py against this WORK_DIR to drive the"
echo "Disk Utility erase + Installer click-through (experimental, see its"
echo "own --calibrate mode first — it needs real screen coordinates from a"
echo "live screenshot before it will attempt anything destructive)."
