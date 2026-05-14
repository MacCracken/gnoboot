# 003 — Cyrius MS x64 ABI under TARGET_EFI

> **Discovered**: 2026-05-13 (Step 4 first-attempt disassembly) | **Subject**: how cyrius `fncallN` dispatches firmware function pointers, and why QEMU smoke tests need `-cpu max`

## What's true about the code

Under `CYRIUS_TARGET_EFI=1`, cyrius **predefines both
`CYRIUS_TARGET_EFI` and `CYRIUS_TARGET_WIN`** (the latter as of
v5.11.52). This is intentional: UEFI Applications and Windows
binaries share the PE32+ container and the MS x64 ABI; cyrius's
stdlib code branches on `TARGET_WIN` for MS-x64-specific calling
conventions, and those branches fire under TARGET_EFI for free.

The relevant cyrius stdlib file:

`lib/fnptr.cyr` — provides `fncall0` through `fncall8`, indirect
function-pointer dispatchers. Under `TARGET_WIN` (and therefore
TARGET_EFI), the asm body uses MS x64 ABI:

- Args 1–4: RCX, RDX, R8, R9
- 32-byte shadow space allocated by the caller before `call`
- Args 5+: stack at `[rsp + 0x20 + (N-5)*8]`

gnoboot's firmware calls use this directly:

```cyrius
include "lib/fnptr.cyr"

# OpenVolume(sfs, &root_out) — 2 args
var rc = fncall2(fn_openvol, sfs, &root_out);

# HandleProtocol(handle, guid, interface_out) — 3 args
var rc = fncall3(fn_hp, handle, &li_guid, &li_out);

# File->Open(file, &new_handle, filename, mode, attrs) — 5 args
var rc = fncall5(fn_open, root, &file_out, &path, 1, 0);
```

No inline asm needed for any firmware call. The MS x64 ABI dance
(shadow space, register order, stack alignment) is handled inside
`fncallN`.

## Internal cyrius fn-call ABI is also MS x64 under TARGET_EFI

A consequence of `TARGET_WIN` being predefined: cyrius's own
fn-to-fn call convention switches to MS x64. Inside `fn efi_main(handle, st)`,
the function prologue saves `RCX` (= handle) and `RDX` (= st) to
local stack slots, *not* `RDI`/`RSI` (which would be SysV).

This is **opposite** of cyrius's TARGET_LINUX behavior. `lib/fnptr.cyr`'s
documenting comment still mentions "cyrius's own SysV convention" —
that comment predates the TARGET_EFI work. Treat the code as
authoritative, not the comment.

## QEMU `-cpu max` is required

The default QEMU `-cpu qemu64` lacks RDRAND. The AGNOS kernel uses
RDRAND in `kaslr_seed()` during `pmm_init` (called from
`core/main.cyr` after `pt_init`). With qemu64 the RDRAND instruction
faults (`#UD`), and either:

- The kernel's IDT handler catches it and silently hangs
- The fault cascades to `#DF` → triple-fault → silent reset

Real iron (NUC AMD / Zen, Intel Ivy Bridge+) supports RDRAND
natively, so this is **QEMU-emulation-only**. `tests/ovmf_smoke.sh`
sets `-cpu max` explicitly.

## Why this matters

- **Don't roll inline asm for firmware calls** unless an arity isn't
  covered by `fncallN` (max is `fncall8` as of cyrius v5.11.x). The
  trampolines are subtle (RSP alignment, shadow space, MS x64 vs SysV
  callee/caller-saved registers). Use the library.
- **Don't strip `-cpu max` from `tests/ovmf_smoke.sh`** thinking it's a
  legacy multiboot-era flag. Without it, QEMU emulation diverges from
  real iron and the smoke test gives false negatives.
- If gnoboot needs to invoke a firmware function not covered by
  `fncallN` (different arity, different ABI shape — e.g. variadic),
  write the trampoline as a separate file in `src/` and document it,
  not inline in `efi_main`.

## Reference

- `lib/fnptr.cyr` (in cyrius's stdlib) — the canonical TARGET_WIN/EFI
  branches with byte-level annotated asm
- cyrius CHANGELOG entry for v5.11.52 — describes the TARGET_WIN
  co-predefine under TARGET_EFI
