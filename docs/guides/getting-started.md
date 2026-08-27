# Getting started with gnoboot

This guide gets gnoboot building, gating, and booting an AGNOS kernel
under QEMU+OVMF. For background on what gnoboot IS and the AGNOS boot
path, see the [README](../../README.md) and the
[architecture notes](../architecture/README.md).

## Prerequisites

- **Cyrius toolchain** at the version pinned in `cyrius.cyml`.
  Install via `cyriusly install <version>` or the canonical
  `curl ...install.sh | sh` pattern that CI uses.
- **OVMF firmware** for runtime testing (Arch: `pacman -S edk2-ovmf`;
  Ubuntu: `apt install ovmf`).
- **Disk-image tools** for the OVMF runtime gate: `parted`, `mtools`,
  `qemu-system-x86`.
- An **AGNOS kernel binary** (`build/agnos` from the agnos repo) if
  you want to exercise the full chain; a synthetic 4-byte ELF magic
  stub is built automatically by the smoke test if no real kernel
  is present.

## Build

```sh
CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI
```

`CYRIUS_TARGET_EFI=1` is **required** — without it, cyrius emits
PE32+ with Windows-CUI subsystem (0x0003), which UEFI firmware
rejects as a non-EFI binary.

## Test

### Structural gate (fast, no QEMU required)

```sh
tests/verify_pe.sh
```

Asserts the emitted PE32+ binary has:

- DOS magic `MZ` at offset 0
- PE signature `PE\0\0` at offset 0x40
- COFF Characteristics `0x0022` (executable, large-address-aware,
  **not** RELOCS_STRIPPED) at offset 0x56
- Subsystem `0x000A` (EFI_APPLICATION) at offset 0x9C
- DllCharacteristics with NX_COMPAT bit (0x0100) set at offset 0x9E

Fast (no firmware emulation). Suitable for every save / every pre-commit.

### OVMF runtime gate (full smoke)

```sh
tests/ovmf_smoke.sh
```

Builds a 64 MB GPT disk image with a single FAT32 ESP partition,
drops in `\EFI\BOOT\BOOTX64.EFI` (your `build/BOOTX64.EFI`) and
optionally `\boot\agnos` (the AGNOS kernel from
`/home/macro/Repos/agnos/build/agnos` if present, else a 4-byte
synthetic stub), boots under `qemu-system-x86_64 -cpu max -machine q35`
with OVMF firmware. Greps the firmware ConOut serial output for the
expected banner.

Default expected banner is `gnoboot v<VERSION>` — derived from the
`VERSION` file by `tests/ovmf_smoke.sh`, and matching the `msg_pre`
banner constant in `src/main.cyr`. Override with `EXPECT="something"`:

```sh
EXPECT="AGNOS kernel v1.30.0" tests/ovmf_smoke.sh
```

Useful for asserting the kernel banner prints (i.e., end-to-end
handoff is working), not just gnoboot's banner.

## Layout

- `src/main.cyr` — single source file. UTF-16LE message constants
  (byte-array literals), EFI GUIDs, `efi_print` helper,
  `fn efi_main(handle, st)`.
- `lib/fnptr.cyr` — vendored cyrius stdlib (`fncallN` MS x64
  firmware-call dispatch). Auto-resolved by `cyrius deps`.
- `tests/verify_pe.sh` — fast structural gate.
- `tests/ovmf_smoke.sh` — runtime gate.
- `build/` — output (gitignored).

## Adding firmware-call code

For any firmware function call:

1. Find the function's offset in the relevant UEFI struct (BootServices,
   FileProtocol, etc.) — these are in the UEFI 2.x spec, Tables 4.4 / 13.5 / etc.
2. Match the function's arg count to the right `fncallN`.
3. Call it:

```cyrius
var bs    = load64(st + 0x60);      # SystemTable->BootServices
var fn_hp = load64(bs + 0x98);      # BootServices->HandleProtocol
var rc    = fncall3(fn_hp, handle, &guid, &out);
```

No inline asm needed. `lib/fnptr.cyr`'s TARGET_WIN branch handles
the MS x64 ABI (shadow space, RCX/RDX/R8/R9 args, stack alignment).

For arities `fncallN` doesn't cover, document a per-call trampoline
in a new architecture note and `include` it from `src/main.cyr`.

## Releasing

```sh
# Bump VERSION
echo "0.1.1" > VERSION

# Add a CHANGELOG entry above [Unreleased] for the new version
$EDITOR CHANGELOG.md

# Tag and push (user-side; gnoboot agents don't push)
git tag v0.1.1
git push origin main --tags
```

The `release.yml` workflow on tag push:

1. Runs `ci.yml` as a gate (structural + OVMF smoke).
2. Verifies `VERSION` matches the tag.
3. Builds `build/BOOTX64.EFI`.
4. Stages `release/BOOTX64.EFI` + `release/gnoboot-X.Y.Z-x86_64-efi.efi`
   + `release/SHA256SUMS`.
5. Creates the GitHub Release via `softprops/action-gh-release@v2`.

## Iron (real hardware) testing

Use `agnosticos/scripts/install-usb.sh` to provision a USB stick
with gnoboot + agnos kernel, then boot the target hardware
(currently the NUC AMD per the iron-boot test log). Capture serial
output via a USB-TTL adapter for forensic continuity.

See [agnosticos iron-nuc-zen log](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iron-nuc-zen-log.md)
for the running log of attempts.
