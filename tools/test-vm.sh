#!/usr/bin/env bash
#
# Boot a built Magnetar ISO in QEMU.
#
# Defaults to UEFI, because that is how the ISO will actually be booted and
# because the BIOS path exercises entirely different bootloader code. Pass
# --bios to test the other one.
#
#   tools/test-vm.sh [path to iso] [--bios] [--install] [--headless]
#
#   --install    attach an empty 40G disk so Calamares has somewhere to go
#   --headless   serial console only, for checking whether it boots at all
#                over SSH or in a log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/branding.env"

iso=""
firmware="uefi"
install_disk=0
headless=0

for arg in "$@"; do
  case "$arg" in
    --bios)     firmware="bios" ;;
    --install)  install_disk=1 ;;
    --headless) headless=1 ;;
    *.iso)      iso="$arg" ;;
    *) echo "test-vm: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

if [[ -z $iso ]]; then
  iso=$(find "$root/build/iso-src/out" -name '*.iso' -newer "$root/branding.env" 2>/dev/null | head -1)
  [[ -n $iso ]] || iso=$(find "$root/build/iso-src/out" -name '*.iso' 2>/dev/null | head -1)
fi
[[ -n $iso && -f $iso ]] || { echo "test-vm: no ISO found. Build one first." >&2; exit 2; }

echo "ISO      : $iso ($(du -h "$iso" | cut -f1))"
echo "firmware : $firmware"

vm="$root/build/vm"
mkdir -p "$vm"

args=(
  -enable-kvm
  -machine q35,accel=kvm
  -cpu host
  -m 6G
  -smp 4
  -drive "file=$iso,media=cdrom,readonly=on"
  -boot order=d
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0
  -device virtio-balloon
  -name "$DISTRO_NAME live"
)

if [[ $firmware == uefi ]]; then
  code=/usr/share/edk2/x64/OVMF_CODE.4m.fd
  [[ -f $code ]] || code=/usr/share/OVMF/OVMF_CODE_4M.fd
  vars="$vm/OVMF_VARS.fd"
  if [[ ! -f $vars ]]; then
    src=/usr/share/edk2/x64/OVMF_VARS.4m.fd
    [[ -f $src ]] || src=/usr/share/OVMF/OVMF_VARS_4M.fd
    cp "$src" "$vars"
  fi
  args+=(
    -drive "if=pflash,format=raw,readonly=on,file=$code"
    -drive "if=pflash,format=raw,file=$vars"
  )
fi

if (( install_disk )); then
  disk="$vm/magnetar-test.qcow2"
  [[ -f $disk ]] || qemu-img create -f qcow2 "$disk" 40G >/dev/null
  args+=(-drive "file=$disk,if=virtio,format=qcow2")
  echo "disk     : $disk"
fi

if (( headless )); then
  # No compositor will come up usefully here — this answers "did the kernel
  # boot and did systemd reach a target", nothing about the desktop.
  args+=(-nographic -serial mon:stdio)
else
  # virtio-gpu with virgl: cosmic-comp needs a DRM device, and software
  # rendering through llvmpipe is slow enough to look like a hang.
  args+=(-device virtio-vga-gl -display gtk,gl=on)
fi

echo
printf 'qemu-system-x86_64'; printf ' %q' "${args[@]}"; echo
echo
exec qemu-system-x86_64 "${args[@]}"
