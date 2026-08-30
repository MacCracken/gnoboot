# 001 — Sovereign handoff contract

> **Discovered**: 2026-05-13 (v0.1.0 Step 7) | **Layout section superseded**: 2026-08-29 (v0.7.1 — see below) | **Subject**: AGNOS kernel entry register state, struct layout, and the irrevocability of `ExitBootServices`

## What's true about the code

When gnoboot completes its boot pipeline and jumps to the AGNOS
kernel entry point, the CPU state matches **exactly** this contract.
Deviation breaks the kernel-side `boot_info_capture_rdi` and any
downstream code that reads `boot_info_ptr`.

| Register | Value at kernel entry |
|---|---|
| RIP | Kernel's ELF `e_entry` for `ET_EXEC`; `load_base + (e_entry - min_paddr)` for an `ET_DYN` PIE kernel (v0.6.0 KASLR). The hardcoded `0x1000A8` in this table's heading is the agnos 1.30.x value and is no longer assumed by gnoboot. |
| RDI | Physical address of `agnos_boot_info` struct (the **sovereign-struct pointer**) |
| RAX | Undefined |
| RCX, RDX, RSI, R8-R11 | Undefined (caller-saved in both ABIs, may hold cyrius/firmware leftovers) |
| RBX, RBP, R12-R15 | Undefined (callee-saved, but no caller to preserve them — kernel must set up its own) |
| RSP | Whatever gnoboot's last stack pointer was (NOT zero, NOT word-aligned guaranteed) |
| CR0 | UEFI's value: PG + PE + ET + NE + WP + MP |
| CR3 | UEFI's PML4 — identity-maps first 4 GB typically |
| CR4 | UEFI's value: PAE + PSE + OSFXSR + OSXMMEXCPT + (maybe SMEP/SMAP) |
| EFER | UEFI's value: LME + NXE set |
| CS | UEFI's 64-bit code segment selector (typically `0x38` on QEMU OVMF) |
| DS/ES/SS | UEFI's data segment selectors |
| Interrupts | Whatever UEFI left. **gnoboot executes no `cli`/`sti` and asserts nothing here** — this row records firmware behaviour inherited from the UEFI spec, not a gnoboot guarantee. A kernel should establish its own interrupt state rather than rely on it. |
| UEFI Boot Services | **Terminated** — gnoboot called ExitBootServices. No more ConOut, AllocatePages, file I/O. |
| UEFI Runtime Services | Available via `boot_info->efi_st_phys->RuntimeServices`. Firmware-dependent reliability. |

## Sovereign boot-info struct

> ⛔ **The layout is no longer duplicated here.** The authoritative field-by-field
> contract is
> [`docs/standards/handoff-protocol.md`](../standards/handoff-protocol.md)
> (roadmap M4, shipped v0.7.1) — every field with its type, offset, absent-value
> and introducing version, plus the compatibility rules and the validation a
> consumer must perform.
>
> **This section used to carry its own copy of the table, and it went stale**:
> it still said `struct_size = 112 (0x70)` with an END tag at `0x68`, three
> generations behind the code (the v0.4.x `fb_size`, the v0.5.0 initramfs /
> cmdline / RSDP fills, the v0.6.0 `kernel_base`, and the v0.7.1 growth to 128
> bytes all landed after it was written). A struct described in three places is
> a struct described wrong in at least one of them; the spec is now the single
> source and this document points at it.

What remains true and specific to *this* document — the things a reader needs
about the code rather than the wire:

- **Magic `0x41474E4F` = `'AGNO'`** little-endian at offset 0, and the kernel
  really does assert it. That was aspirational when this document was written in
  2026-05; it became true at **agnos 1.56.51**, which validates magic and
  `struct_size` before trusting the pointer and leaves `boot_info_ptr` zero on
  failure so every downstream guard engages.
- **Wire version 2**, unchanged since the v0.1.0 canary build. The framebuffer
  fields are *inlined at fixed offsets* rather than delivered as tags precisely
  so the agnos boot-shim canary can read `fb_phys` from raw assembly at entry
  instruction #1, before a stack exists — walking a tag stream there is brutal.
  See iron-nuc-zen-log § Attempt 6. That single constraint is why the struct is
  flat, and the spec's § 6 now makes "flat, forever" an explicit rule.
- **The struct lives in the gnoboot binary's globals**, populated at runtime —
  not in fresh `AllocatePages` memory. It is small, and post-EBS it is
  conventional RAM classified `EfiLoaderCode`/`EfiLoaderData` in the memmap. The
  same is true of the memory map buffer that `memmap_phys` points at. **The
  kernel must copy both before reclaiming loader memory** — see the spec's § 7
  for the full ownership table.

## Constraints implied

1. **`ExitBootServices` is irrevocable.** After EBS returns success,
   there is no path back to UEFI Boot Services. Any code path that
   calls firmware services (efi_print, AllocatePages, file I/O) must
   complete *before* EBS.
2. **The memmap must be fresh.** Any firmware service call between
   `GetMemoryMap` and `ExitBootServices` may invalidate the `mm_key`,
   and EBS will return `EFI_INVALID_PARAMETER`. gnoboot's pattern: do
   GetMemoryMap, *no firmware calls*, EBS. (efi_print before
   GetMemoryMap is fine; after is not.)
3. **No diagnostic output post-EBS.** ConOut is gone. The only output
   surface is whatever the kernel sets up via its own UART driver
   (agnos initializes COM1 at `0x3F8` in the boot shim). Errors in
   the jump path that occur after EBS are silent resets unless OVMF's
   exception handler is still alive (firmware-dependent).
4. **`RDI` is the only contract.** All other registers are scratch
   from the kernel's perspective. agnos's boot shim does not read
   RAX/RCX/RSI/etc. The kernel sets up its own stack at `0x200000`
   (first non-shim instruction), so RSP is also implicitly scratch.
5. **The struct must outlive `ExitBootServices`.** Cyrius globals
   live in `.bss`, mapped into the loader's address space, which
   *post-EBS* is conventional RAM. The kernel reads the struct from
   physical `&boot_info` (= load-time virtual = post-EBS physical,
   under UEFI's identity map). The struct stays valid until either
   the kernel reclaims `EfiLoaderData` regions or it overwrites the
   page deliberately.

## Why this matters

The handoff contract is the **single load-bearing interface** between
gnoboot and the kernel. Every other layer of gnoboot (file I/O, ELF
parsing, AllocatePages) is replaceable; the handoff is not. Changes
to this contract are breaking-changes that bump gnoboot's major version
and require synchronized agnos changes.
