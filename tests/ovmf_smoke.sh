#!/bin/sh
# tests/ovmf_smoke.sh — boot build/BOOTX64.EFI under QEMU + OVMF, assert banner.
#
# Builds a 64MB GPT disk with an ESP partition at 1MiB offset, copies
# build/BOOTX64.EFI to /EFI/BOOT/BOOTX64.EFI on that ESP, then boots
# under qemu-system-x86_64 with OVMF firmware. Greps the ConOut serial
# output for the expected banner string.
#
# Layout matches cyrius's own _efi_ovmf_smoke_gate (cyrius/programs/check.cyr) —
# GPT-disk-with-ESP via parted + mtools is the only known-working
# combination for OVMF UEFI handoff (raw FAT images get "Not Found").
#
# Usage:
#   tests/ovmf_smoke.sh                           # uses build/BOOTX64.EFI
#   tests/ovmf_smoke.sh /path/to/BOOTX64.EFI      # custom binary
#   EXPECT="gnoboot v0.1.0" tests/ovmf_smoke.sh   # custom expected line
#
# Requires: qemu-system-x86_64, parted, mtools (mformat/mmd/mcopy),
# edk2-ovmf (Arch: pacman -S edk2-ovmf qemu-base parted mtools).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EFI="${1:-$ROOT/build/BOOTX64.EFI}"
EXPECT="${EXPECT:-gnoboot v0.1.0}"
OVMF_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
OVMF_VARS_SRC="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"

# Tooling probes — graceful SKIP shape mirrors cyrius check.sh.
for tool in qemu-system-x86_64 parted mformat mmd mcopy; do
    command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not in PATH"; exit 0; }
done
[ -f "$OVMF_CODE" ] || { echo "SKIP: $OVMF_CODE not found"; exit 0; }
[ -f "$OVMF_VARS_SRC" ] || { echo "SKIP: $OVMF_VARS_SRC not found"; exit 0; }
[ -f "$EFI" ] || { echo "ERROR: $EFI not found — run \`CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI\` first" >&2; exit 1; }

D=$(mktemp -d -t gnoboot-smoke.XXXXXX)
trap 'rm -rf "$D"' EXIT
cd "$D"

dd if=/dev/zero of=disk.img bs=1M count=64 status=none
parted -s disk.img mklabel gpt mkpart ESP fat32 1MiB 100% set 1 esp on >/dev/null 2>&1
mformat -i disk.img@@1048576 -F
mmd -i disk.img@@1048576 ::EFI
mmd -i disk.img@@1048576 ::EFI/BOOT
mcopy -i disk.img@@1048576 "$EFI" ::EFI/BOOT/BOOTX64.EFI

cp "$OVMF_VARS_SRC" vars.fd
chmod +w vars.fd

OUTPUT=$(timeout 12 qemu-system-x86_64 \
    -machine q35 -m 256M \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=vars.fd" \
    -drive "file=disk.img,format=raw" \
    -serial stdio -display none -no-reboot 2>/dev/null || true)

if echo "$OUTPUT" | grep -q "$EXPECT"; then
    echo "PASS: \"$EXPECT\" observed on ConOut"
    exit 0
else
    echo "FAIL: \"$EXPECT\" not observed"
    echo "----- captured serial -----"
    echo "$OUTPUT" | tail -20
    echo "---------------------------"
    exit 1
fi
