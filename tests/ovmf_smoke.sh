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
#   EXPECT="gnoboot v0.2.0" tests/ovmf_smoke.sh   # custom expected line
#
# Requires: qemu-system-x86_64, parted, mtools (mformat/mmd/mcopy),
# edk2-ovmf (Arch: pacman -S edk2-ovmf qemu-base parted mtools).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EFI="${1:-$ROOT/build/BOOTX64.EFI}"
EXPECT="${EXPECT:-gnoboot v0.3.0: handing off to kernel}"

# OVMF firmware paths differ between distros — probe both common
# locations. Arch: edk2-ovmf installs to /usr/share/edk2-ovmf/x64/
# with `.4m.fd` suffix. Ubuntu: ovmf installs to /usr/share/OVMF/
# without the `.4m.fd` suffix. First match wins.
OVMF_CODE=""
OVMF_VARS_SRC=""
for c in \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/qemu/OVMF.fd \
    ; do
    if [ -f "$c" ]; then OVMF_CODE="$c"; break; fi
done
for v in \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    ; do
    if [ -f "$v" ]; then OVMF_VARS_SRC="$v"; break; fi
done

# Tooling probes — graceful SKIP shape mirrors cyrius check.sh.
for tool in qemu-system-x86_64 parted mformat mmd mcopy; do
    command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not in PATH"; exit 0; }
done
[ -n "$OVMF_CODE" ]     || { echo "SKIP: OVMF_CODE.fd not found (tried Arch + Ubuntu paths)"; exit 0; }
[ -n "$OVMF_VARS_SRC" ] || { echo "SKIP: OVMF_VARS.fd not found"; exit 0; }
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

# Optional: drop an `/boot/agnos` payload on the ESP so Step 5+ smoke
# tests can open and read it. $AGNOS_KERNEL overrides; default tries
# the local agnos build, then synthesizes a 4-byte ELF-magic file.
AGNOS_KERNEL="${AGNOS_KERNEL:-$ROOT/../agnos/build/agnos}"
if [ -f "$AGNOS_KERNEL" ]; then
    mmd -i disk.img@@1048576 ::boot 2>/dev/null || true
    mcopy -i disk.img@@1048576 "$AGNOS_KERNEL" ::boot/agnos
elif [ "${SYNTH_ELF:-1}" = "1" ]; then
    # 4-byte fake: ELF magic only. Enough for "ELF" classification.
    printf '\x7FELF' > agnos_stub
    mmd -i disk.img@@1048576 ::boot 2>/dev/null || true
    mcopy -i disk.img@@1048576 agnos_stub ::boot/agnos
fi

cp "$OVMF_VARS_SRC" vars.fd
chmod +w vars.fd

# -cpu max advertises RDRAND + SMEP + SMAP. The default qemu64 CPU
# lacks RDRAND; the AGNOS kernel uses it in kaslr_seed() during
# pmm_init() and faults (silently — IDT is installed but the #UD
# default handler doesn't propagate). On real iron (NUC AMD / Zen)
# RDRAND is supported natively, so this flag is QEMU-emulation-only.
# QEMU_TIMEOUT defaults to 20s (was 12s) — the kernel boot reaches
# the scheduler/userland tests within ~15s; raise for slower CI.
OUTPUT=$(timeout "${QEMU_TIMEOUT:-20}" qemu-system-x86_64 \
    -machine q35 -m 256M -cpu max \
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
