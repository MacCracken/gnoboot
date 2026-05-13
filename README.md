# gnoboot

Sovereign Cyrius-native UEFI bootloader for AGNOS. Replaces GRUB on
the boot path. Loads the AGNOS kernel from the ESP, builds a sovereign
boot-info struct, calls `ExitBootServices`, jumps to kernel entry.

Brought forward to MVP-critical 2026-05-13 after GRUB's multiboot2-EFI
relocator was found to write to its own `.text` and fault under
modern strict-W^X UEFI (see `agnosticos/docs/development/iron-boot-testing-log.md`
§ *Diagnosis 2*). The AGNOS sovereignty pattern (cyrius replaced
gcc/clang/llvm; agnos replaced Linux) eats GRUB next.

## Status

| Step | Description | Status |
|------|-------------|--------|
| 3 | Console banner via SystemTable→ConOut→OutputString | ✓ 2026-05-13 (boots under QEMU OVMF) |
| 4 | ESP file read (open SimpleFileSystem, read `/boot/agnos`) | pending |
| 5 | ELF64 parse + AllocatePages + LOAD-segment copy | pending |
| 6 | GetMemoryMap | pending |
| 7 | Sovereign boot-info struct build + ExitBootServices + jump | pending |
| 8 | Agnos shim swap MB2→sovereign struct (cross-repo) | pending |
| 9 | End-to-end gnoboot → agnos kernel under QEMU OVMF | pending |
| 12 | Iron Attempt 5 on NUC AMD | pending |

Full plan: `agnosticos/docs/development/path-c-sovereign-uefi.md`.

## Build

```sh
CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI
```

`CYRIUS_TARGET_EFI=1` selects the UEFI Application emit mode added in
cyrius 5.11.49 — PE32+ with `Subsystem = 0x0A (IMAGE_SUBSYSTEM_EFI_APPLICATION)`,
no Win32 import table, populated `.reloc`, NX_COMPAT, RELOCS_STRIPPED
cleared.

## Test

```sh
tests/ovmf_smoke.sh
```

Builds a 64MB GPT disk with an ESP at 1MiB offset, copies
`build/BOOTX64.EFI` to `\EFI\BOOT\BOOTX64.EFI` on that ESP, boots under
QEMU + OVMF, and greps for the expected banner on the firmware ConOut
serial. SKIPs gracefully if `qemu-system-x86_64`, `parted`, `mtools`,
or `edk2-ovmf` is not installed.

## Architecture

UEFI firmware loads `\EFI\BOOT\BOOTX64.EFI` (= gnoboot) directly — no
GRUB on the boot path. Entry contract (MS x64 ABI):

| Register | Value |
|----------|-------|
| RCX      | `EFI_HANDLE ImageHandle` |
| RDX      | `EFI_SYSTEM_TABLE *SystemTable` |
| RSP      | firmware-provided stack |
| (return) | `EFI_STATUS` in RAX |

Cyrius emits a 5-byte `e9 00 00 00 00` (jmp +0) prologue at `.text+0`
that touches no GPRs, so RCX/RDX from firmware survive into our first
user byte.

Handoff to the AGNOS kernel uses a sovereign boot-info struct (magic
`0x41474E4F = 'AGNO'`, pointer in `RDI` per SysV ABI). Versioned, with
inlined critical fields (initramfs, cmdline, memmap pointer, ACPI RSDP,
UEFI SystemTable for post-EBS runtime services) + an extensible tag
stream. Spec: `docs/handoff-protocol.md` (to be written at Step 7).

## License

GPL-3.0-only — matches the AGNOS family.

## Related

- [cyrius](https://github.com/MacCracken/cyrius) — sovereign systems language; UEFI emit mode in 5.11.49
- [agnos](https://github.com/MacCracken/agnos) — AGNOS kernel (ELF64, gnoboot reads this)
- [agnosticos](https://github.com/MacCracken/agnosticos) — AGNOS genesis repo (docs, install scripts, iron-boot test log)
