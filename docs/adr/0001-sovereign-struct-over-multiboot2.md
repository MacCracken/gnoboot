# 0001 — Sovereign boot-info struct over multiboot2

> **Status**: Accepted (2026-05-13, v0.1.0)
> **Decision-makers**: AGNOS project lead + gnoboot/agnos agents
> **Affects**: AGNOS kernel ABI; bootloader contract; downstream toolchain

## Context

In May 2026, the AGNOS boot path was being staged Path A (ELF64 +
multiboot2 via GRUB) for MVP, with Path C (sovereign UEFI bootloader)
as the long-term destination. Path A's implementation in cyrius
5.11.43 was technically correct: `EMITELF64_KERNEL` produced a valid
multiboot2 ELF64 binary that GRUB's `grub-file --is-x86-multiboot2`
accepted.

Path A then died for a reason no agnos/gnoboot work could fix: GRUB's
`grub_relocator64_efi_boot` (the EFI multiboot2 handoff trampoline
in upstream GRUB) writes the kernel register state directly into
its own `.text` section before the `iretq` to the kernel. Under
modern UEFI firmware that enforces W^X on code pages via the Memory
Attributes Protocol (OVMF 2024+, likely most production firmware),
those writes fault. Linux distros don't hit this because they boot
via `linuxefi` (a different relocator); multiboot2 + GRUB-EFI is a
genuinely under-tested path.

Three options were considered:

1. **Patched GRUB**: vendor a fork with the relocator fixed.
   Carries a long maintenance tail; throws away the work when Path C
   eventually lands anyway.
2. **Linux Boot Protocol pretender**: make AGNOS pretend to be a
   bzImage for GRUB's `linuxefi`. Wastes cyrius's multiboot2 emit
   work; ties AGNOS's boot ABI to Linux's protocol in perpetuity.
   Anti-sovereignty.
3. **Bring Path C forward**: build gnoboot as the MVP boot path.
   Drops GRUB entirely. Real engineering scope (~2000 LoC), but the
   cleanest endpoint and the one the roadmap was already pointing at.

Choosing Path C made the **handoff contract** a decision in its own
right. Three sub-options:

3a. **Reuse multiboot2's MBI format** — gnoboot synthesizes the same
    tag-stream MBI the GRUB+multiboot2 path would have. agnos kernel's
    shim parses it identically. Pro: kernel-side parser code reuses
    Path A work. Con: ties AGNOS to a protocol it doesn't control;
    can't add AGNOS-specific fields without forking the spec.

3b. **Linux Boot Protocol** — gnoboot builds a bzImage-shape handoff,
    kernel parses Linux's setup_header + zero-page. Pro: well-tested
    protocol. Con: same as option 2 above — anti-sovereignty.

3c. **Sovereign struct** — design an AGNOS-native handoff. Versioned,
    extensible via tag-stream, magic `'AGNO'`. Pro: AGNOS owns its
    own boot ABI end-to-end. Con: net-new design + spec doc + spec
    discipline (no random additions, every change is a major version
    bump).

## Decision

Option 3 (Path C) + Option 3c (sovereign struct).

The handoff contract:
- Magic: `0x41474E4F = 'AGNO'`
- Register: `RDI = &boot_info` (per SysV ABI calling convention for
  the first arg; convenient for kernel reads)
- Layout: 80 bytes inlined fields + extensible tag stream (END
  terminator = `type 0`)

## Consequences

**Wins:**
- AGNOS owns its boot path top-to-bottom. No third-party
  bootloader, no third-party protocol, no third-party W^X policy
  to navigate.
- Forward-extensible without breaking compat. Reserved tag types
  let us add fields (framebuffer info, IOAPIC hints, etc.) without
  changing the v1 contract.
- The cyrius multiboot2 + EFI64 work in 5.11.43 is preserved (still
  emits a valid kernel binary; only the handoff protocol changed,
  not the kernel ELF shape).

**Costs:**
- gnoboot becomes a real subsystem (its own repo, its own release
  cadence, its own CI). ~2000 LoC of cyrius code.
- agnos kernel shim swaps from MBI-tag parsing to sovereign-struct
  field access. Small diff (~10 lines for the asm capture; the MBI
  tag walker was never built since the kernel hadn't reached MBI
  consumption yet).
- We're not multiboot2-compatible anymore. Other bootloaders
  (Limine, Tianocore, etc.) can't boot AGNOS without their own
  sovereign-struct adapter. This is by design.
- Long-term maintenance of the handoff spec. The spec doc (when
  written, slated for gnoboot v0.5) becomes a load-bearing AGNOS
  artifact.

## Status of related items

- **Path A**: dead. Cyrius 5.11.43's `EMITELF64_KERNEL` stays in the
  language as latent capability (kernel binary is still ELF64
  multiboot2-compatible by shape; only the handoff register
  convention changed).
- **Cyrius 5.11.49**: adds `_TARGET_EFI_APPLICATION` PE32+ emit. Required
  for gnoboot to compile. Filed by gnoboot's bring-up.
- **Cyrius 5.11.51 / 5.11.52 / 5.11.53**: ergonomic improvements
  (byte-array literal, `fn efi_main` convention, REX-prefix hotfix).
  All filed during gnoboot's bring-up; all landed within hours.
- **agnos 1.30.0**: cuts the kernel ABI break. `mbi_capture_rbx →
  boot_info_capture_rdi`, asm byte `0x18 → 0x38`.

## References

- [agnosticos path-c plan](https://github.com/MacCracken/agnosticos/blob/main/docs/development/path-c-sovereign-uefi.md)
- [agnosticos iron-nuc-zen log § Diagnosis 2](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iron-nuc-zen-log.md)
- gnoboot architecture note [001 — Sovereign handoff contract](../architecture/001-sovereign-handoff-contract.md)
