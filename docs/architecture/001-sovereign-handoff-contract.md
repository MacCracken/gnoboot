# 001 — Sovereign handoff contract

> **Discovered**: 2026-05-13 (v0.1.0 Step 7) | **Subject**: AGNOS kernel entry register state, struct layout, and the irrevocability of `ExitBootServices`

## What's true about the code

When gnoboot completes its boot pipeline and jumps to the AGNOS
kernel entry point, the CPU state matches **exactly** this contract.
Deviation breaks the kernel-side `boot_info_capture_rdi` and any
downstream code that reads `boot_info_ptr`.

| Register | Value at kernel entry (`0x1000A8`) |
|---|---|
| RIP | Kernel's ELF e_entry (`0x1000A8` for agnos 1.30.x) |
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
| Interrupts | Disabled (UEFI sets `cli` before EBS handoff per spec) |
| UEFI Boot Services | **Terminated** — gnoboot called ExitBootServices. No more ConOut, AllocatePages, file I/O. |
| UEFI Runtime Services | Available via `boot_info->efi_st_phys->RuntimeServices`. Firmware-dependent reliability. |

## Sovereign boot-info struct (112 bytes — v2 wire)

Magic `0x41474E4F = 'AGNO'` little-endian at offset 0. Kernel asserts
this byte sequence to refuse foreign bootloaders.

**Version 2** is the current wire (bumped from v1 in v0.1.0 canary
build to inline the framebuffer fields at 0x48-0x60 so the agnos
boot-shim canary can read `fb_phys` from raw asm at entry instruction
#1 without walking a tag stream; see iron-nuc-zen-log § Attempt 6 +
gnoboot/src/main.cyr inline layout comment).

```
0x00  u32   magic            = 0x41474E4F ('AGNO')
0x04  u32   version          = 2
0x08  u32   struct_size      = 112 (0x70)
0x0C  u32   flags            (bit 0=serial, bit 1=fb_present)
0x10  u64   initramfs_phys   (0 in v0.1.0)
0x18  u64   initramfs_size   (0 in v0.1.0)
0x20  u64   cmdline_phys     (0 in v0.1.0)
0x28  u64   memmap_phys      → first byte of EFI_MEMORY_DESCRIPTOR[] array
0x30  u32   memmap_count     count of entries
0x34  u32   memmap_entsize   firmware-reported descriptor size (0x30 / 0x38)
0x38  u64   acpi_rsdp_phys   (0 in v0.1.0)
0x40  u64   efi_st_phys      EFI SystemTable* (for RuntimeServices post-EBS)
0x48  u64   fb_phys          GOP Mode->FrameBufferBase (0 = no fb)
0x50  u32   fb_pitch         bytes per scanline (ppl * 4, 32-bpp assumed)
0x54  u32   fb_width         GOP Info->HorizontalResolution
0x58  u32   fb_height        GOP Info->VerticalResolution
0x5C  u32   fb_pixel_format  0=RGB 1=BGR 2=Bitmask 3=BltOnly
0x60  u32   fb_mode_current  GOP Mode->Mode    (which mode firmware booted)
0x64  u32   fb_mode_max      GOP Mode->MaxMode (how many modes available)
0x68  tag[] type=0 END
```

**0x60 / 0x64 overlay**: `fb_mode_current` and `fb_mode_max` overlay
the previously-reserved u64 at 0x60. **No version bump** because v2
readers ignored those 8 bytes — readers that don't know about the
overlay still work, readers that do know it use the values. Added in
agnos 1.30.12 / gnoboot 0.2.x to surface GOP mode # for quiet-boot vs
VGA-spec divergence diagnosis (see agnosticos `iron-nuc-zen-log.md`
1.30.12 entry).

The struct lives in the gnoboot binary's `.bss` (cyrius global,
populated at runtime). After `ExitBootServices`, this memory is
classified as `EfiLoaderData` in the memmap — kernel may reclaim
once it's done reading. gnoboot does not deliberately allocate the
struct in fresh AllocatePages memory because (a) it's small (112 B)
and (b) the kernel will recover all `EfiLoaderData` regions as
free RAM after it parses the memmap.

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
