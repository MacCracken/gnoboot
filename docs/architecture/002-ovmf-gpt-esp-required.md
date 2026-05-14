# 002 — OVMF requires GPT-disk-with-ESP

> **Discovered**: 2026-05-13 (Step 3 smoke-test bring-up) | **Subject**: why `tests/ovmf_smoke.sh` uses parted + mtools instead of a raw FAT image

## What's true about the code

UEFI firmware (OVMF specifically, but also most real-iron implementations)
**requires a GUID Partition Table with an ESP (EFI System Partition)**
to resolve the removable-boot path `\EFI\BOOT\BOOTX64.EFI`. A raw
FAT32 image (no partition table) is **not** recognized as a bootable
ESP by OVMF's `BdsDxe` (Boot Device Selection DXE driver), even though
the image is structurally a valid FAT32 filesystem.

Failure mode: `BdsDxe: failed to load Boot0002 "UEFI QEMU HARDDISK
QM00001 ": Not Found`.

## Required layout

```
GPT disk (≥ 64 MB recommended)
├── (1 MiB padding before first partition)
├── Partition 1: ESP
│   ├── Type GUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B (EFI System Partition)
│   ├── FAT32 formatted
│   ├── `esp on` flag set (parted's term; sets GPT attribute)
│   └── Contents:
│       └── EFI/
│           └── BOOT/
│               └── BOOTX64.EFI    ← gnoboot binary, by removable-boot convention
```

## How `tests/ovmf_smoke.sh` builds this

```sh
dd if=/dev/zero of=disk.img bs=1M count=64 status=none
parted -s disk.img mklabel gpt mkpart ESP fat32 1MiB 100% set 1 esp on >/dev/null 2>&1
mformat -i disk.img@@1048576 -F
mmd -i disk.img@@1048576 ::EFI ::EFI/BOOT
mcopy -i disk.img@@1048576 build/BOOTX64.EFI ::EFI/BOOT/BOOTX64.EFI
```

The `@@1048576` offset is the 1 MiB start of the ESP partition (in
bytes), telling mtools to treat the image as if the ESP began at that
offset.

## Real iron implication

The same constraint applies to USB sticks for iron testing. `install-usb.sh`
in agnosticos creates the same layout (GPT + ESP + 1 MiB offset).

## Lesson

The first gnoboot Step-3 smoke attempt used a raw FAT image and got
the `Not Found` error. The cyrius project's own EFI smoke test
(`programs/check.cyr` → `_efi_ovmf_smoke_gate`) used the GPT layout,
which was the reference that unblocked us. Copy the cyrius pattern
when in doubt about EFI disk image format — they've already debugged it.
