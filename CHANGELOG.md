# Changelog

All notable changes to gnoboot will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Working toward **v0.1.0** — Step 9 of the Path C plan
(`agnosticos/docs/development/path-c-sovereign-uefi.md`): end-to-end
gnoboot → AGNOS kernel boot through QEMU OVMF, plus iron Attempt 5
on the NUC AMD. v0.1.0 will not be tagged until both gates pass.

### Added

- Initial scaffold (cyrius.cyml pinned to cyrius **5.11.49** — UEFI
  Application emit mode), VERSION 0.1.0, GPL-3.0-only.
- `src/main.cyr` — Step 3 banner. Prints `"gnoboot v0.1.0"` to firmware
  ConOut via `SystemTable->ConOut->OutputString`, returns EFI_SUCCESS.
  Pattern mirrors `cyrius/programs/efi_probe.cyr`: single inline-asm
  block, no DIR64 fixups needed at banner scale.
- `tests/verify_pe.sh` — fast structural gate. Verifies DOS magic at
  0x00, PE signature at 0x40, COFF Characteristics 0x0022 (no
  RELOCS_STRIPPED) at 0x56, Subsystem 0x000A (EFI_APPLICATION) at
  0x9C, DllCharacteristics 0x0100 (NX_COMPAT) at 0x9E.
- `tests/ovmf_smoke.sh` — runtime end-to-end gate. Builds a 64MB GPT
  disk with ESP at 1MiB, drops in `\EFI\BOOT\BOOTX64.EFI`, boots under
  qemu-system-x86_64 + OVMF, asserts the expected banner appears on
  the firmware ConOut serial. Cross-distro OVMF path probing (Arch
  `edk2-ovmf` + Ubuntu `ovmf`).
- `.github/workflows/ci.yml` — Install cyrius (canonical install.sh +
  post-install smoke per the agnos pattern), build with
  `CYRIUS_TARGET_EFI=1`, run structural + OVMF smoke gates, upload
  `BOOTX64.EFI` as an artifact.
- `.github/workflows/release.yml` — Triggered on `v?X.Y.Z` tags. CI
  must pass first; then version-verify, build, structural gate, and
  publish `BOOTX64.EFI` + `gnoboot-X.Y.Z-x86_64-efi.efi` + `SHA256SUMS`
  to a GitHub release with auto-generated notes.

### Verified (this branch)

- 2026-05-13 — Step 3 banner observed on QEMU OVMF ConOut. Structural
  gate `tests/verify_pe.sh` reports all 5 PE-header fields PASS.
  Runtime gate `tests/ovmf_smoke.sh` reports
  `PASS: "gnoboot v0.1.0" observed on ConOut`.
- 2026-05-13 — **Step 4a probe** PASS as printed, but the
  *interpretation* was wrong. The probe printed "step 4a probe ok"
  on ConOut, but Step 4's disassembly later revealed that the
  `var p = &global; asm { mov [rax], rdx }` capture was a no-op —
  cyrius reorders the asm to emit BEFORE the `&global` lea, so RAX
  is junk when the `mov [rax], rdx` runs (memory corruption at an
  unknown address). The post-capture print only worked because it
  walked SystemTable→ConOut→OutputString via firmware-preserved
  RDX directly, never reading from the (uncaptured) global. The
  agnos shim's `var p = &foo; asm` pattern works *inside a fn body*
  (locals get inline emit at the source position) but **NOT at
  top-level `kernel;` mode** (top-level `var X = expr;` is treated
  as a global with deferred initializer). Constraint logged.
- 2026-05-13 — **Step 4 (pure-asm)** PASS:
  `step 4: HandleProtocol(LoadedImage) = ok` observed on ConOut.
  First successful MS x64 ABI firmware call from gnoboot. Pattern:
  one top-level `asm { ... }` block, no interleaved cyrius
  statements; firmware args (RCX = ImageHandle, RDX = SystemTable)
  saved into RBX/R12 (callee-saved in both ABIs) immediately after
  the cyrius e9 prologue; OUT parameter for HandleProtocol lives on
  the stack (allocated by `push 0` for writable u64); UTF-16LE
  strings + the LoadedImage GUID embedded as raw bytes inside the
  asm block and addressed via `lea rdx, [rip + disp32]` with
  hand-computed displacements.
- 2026-05-13 — `verify_pe.sh` DllCharacteristics check relaxed:
  asserts NX_COMPAT (0x0100) bit set, not the exact 0x0100 value.
  Cyrius emits DYNAMIC_BASE + HIGH_ENTROPY_VA (0x0060) too when the
  binary has base relocations — both reloc-empty (Step 3 / Step 4
  pure-asm) and reloc-populated (later steps, once we use cyrius
  globals inside a fn) shapes now pass.

### v5.11.52 migration (2026-05-13)

- Pin bumped 5.11.49 → 5.11.52. Both gnoboot-filed enhancement
  issues landed:
    - **Byte-array literal `var foo[N] = { 0x.., ... };`** (v5.11.51)
      — used for `msg_pre` / `msg_ok` / `msg_fail` / `li_guid`.
      ~150 lines of `store8` runs collapsed to four brace lists.
    - **`fn efi_main(handle, st)` convention + lib/fnptr.cyr
      TARGET_WIN fires under TARGET_EFI** (v5.11.52). Replaces
      gnoboot's hand-rolled SysV→MS-x64 entry trampoline + the
      hand-rolled firmware-call asm trampolines. `fncall2` /
      `fncall3` now do the right MS-x64 ABI dance natively.
- **Caveat — cyrius 5.11.52 entry-save REX bug.** The auto-emitted
  save at the entry-jmp target encodes `mov rsi, r9; mov rdi, r10`
  (REX.R extension) where it intended `mov r14, rcx; mov r15, rdx`
  (needs REX.B extension for r14/r15 as destination). Firmware's
  RCX/RDX are NOT saved; the call-site restore later pulls
  undefined R14/R15. gnoboot's six-byte corrective save at the end
  of top-level user code (`asm { 49 89 CE; 49 89 D7 }`) patches
  R14/R15 with the correct values before gvar_inits clobber RCX/RDX.
  Cyrius's broken save happens *before* user code (clobbers RSI/RDI
  but spares RCX/RDX — happily benign). Filed at
  `cyrius/docs/development/issues/2026-05-13-efi-main-trampoline-save-rex-wrong.md`.
  Remove the corrective asm once 5.11.53+ ships the fix.

### Step 6 verified (2026-05-13)

`tests/ovmf_smoke.sh` PASS:
`step 6: kernel @ 0x100000 + memmap = ok` observed on ConOut.
One additional firmware call (`bs->GetMemoryMap`) layered on top of
Step 5b's full chain.

GetMemoryMap state captured into globals for ExitBootServices later:
`mm_buf[2048]` (16 KB; ~400 descriptors of slack — OVMF normally
returns 30-80), `mm_size`, `mm_key`, `mm_dsz`, `mm_dver`. The
`mm_key` is what `ExitBootServices(handle, mm_key)` will require —
firmware rejects any stale snapshot key with EFI_INVALID_PARAMETER.

### Step 5b verified (2026-05-13)

`tests/ovmf_smoke.sh` PASS:
`step 5b: kernel mapped at 0x100000 = ok` observed on ConOut. Full
ELF64 load:

1. Read ELF header (64 bytes from file offset 0), verify ELF magic.
2. Extract `e_phoff` from offset 0x20 of the ELF header.
3. `file->SetPosition(file, e_phoff)`, read first program header (56 B).
4. Verify `p_type == 1` (PT_LOAD). AGNOS kernel ships with exactly
   one PT_LOAD covering `.text` + `.rodata` + `.bss`.
5. Read `p_paddr` (0x100000), `p_offset` (0), `p_filesz` (0x3D350),
   `p_memsz` (0x4D350) from the program header.
6. `bs->AllocatePages(AllocateAddress=2, EfiLoaderData=2,
   pages=ceil(p_memsz/0x1000)=78, &p_paddr)` — fixed-address alloc
   at 0x100000 succeeds on OVMF (firmware reserves below 1 MB but
   not at the 1 MB mark itself).
7. `file->SetPosition(file, p_offset)`, then
   `file->Read(file, &size=p_filesz, p_paddr)` — 245 KB write
   directly to physical 0x100000.
8. Read back first 4 bytes from `0x100000`, compare to ELF magic
   `7F 45 4C 46` — kernel is at the load address.

Notable: OVMF doesn't gate the load-time write to AllocateAddress'd
EfiLoaderData pages — the W^X "no-execute" enforcement only bites
at the time of execution (Step 7's concern). For now, write
succeeds cleanly.

### Step 5 verified on cyrius 5.11.53 (2026-05-13)

`tests/ovmf_smoke.sh` PASS: `step 5: /boot/agnos magic = ELF`
observed on ConOut. Five firmware calls chained, all clean cyrius:

1. `bs->HandleProtocol(ImageHandle, &LoadedImageGuid, &li_out)` →
   LoadedImage pointer.
2. `bs->HandleProtocol(LoadedImage->DeviceHandle, &SimpleFsGuid, &sfs_out)` →
   SimpleFileSystem pointer on the device gnoboot was loaded from.
3. `sfs->OpenVolume(sfs, &root_out)` → root EFI_FILE_PROTOCOL*.
4. `root->Open(root, &file_out, "\boot\agnos", EFI_FILE_MODE_READ, 0)` →
   file handle.
5. `file->Read(file, &size=4, &buf)` → first 4 bytes of the kernel.

ELF magic check (`buf[0..4] == 7F 45 4C 46`) confirms a real ELF
header. The agnos kernel binary at `/home/macro/Repos/agnos/build/agnos`
(251 KB, ELF64) is the test payload, copied onto the test ESP by
`tests/ovmf_smoke.sh` (script auto-detects the kernel build, falls
back to a 4-byte synthetic ELF-magic stub if absent).

Two byte-array-literal sizing errors caught during build (`msg_li_fail`
at 18 bytes in N=2=16 cap, `msg_sfs_fail` at 20 bytes in N=2=16 cap)
— bumped to N=3. Cyrius's error reported line 22 (a blank line) for
the first overflowing array; the actual array is later in the source.
Minor papercut, not file-worthy yet — re-check if it bites again.

Cyrius 5.11.53's hotfix (entry-save REX prefix `4C → 49`) verified:
disassembly at the entry-jmp target now shows the correct
`49 89 CE; 49 89 D7` (`mov r14, rcx; mov r15, rdx`). The corrective
save asm that workaround'd 5.11.52 has been removed from `src/main.cyr`.

### Step 4 verified post-5.11.52 (2026-05-13)

`tests/ovmf_smoke.sh` PASS:
`step 4: HandleProtocol(LoadedImage) = ok` observed on ConOut.
The shape that worked:

```cyrius
kernel;

include "lib/fnptr.cyr"

var msg_pre[10]  = { 0x73,0x00, ... };   # UTF-16LE banner
var li_guid[2]   = { 0xA1,0x31,0x1B,0x5B, ... };
var li_out[1];

fn efi_print(st, msg): i64 {
    var con_out = load64(st + 0x40);
    var out_str = load64(con_out + 0x08);
    return fncall2(out_str, con_out, msg);
}

fn efi_main(handle, st): i64 {
    efi_print(st, &msg_pre);
    var bs    = load64(st + 0x60);
    var fn_hp = load64(bs + 0x98);
    var rc    = fncall3(fn_hp, handle, &li_guid, &li_out);
    if (rc == 0) { efi_print(st, &msg_ok); }
    else         { efi_print(st, &msg_fail); }
    return 0;
}

# Six-byte corrective save (removable post-5.11.53 fix)
asm {
    0x49; 0x89; 0xCE;    # mov r14, rcx
    0x49; 0x89; 0xD7;    # mov r15, rdx
}
```

### Known cyrius constraints (informed Step 4 design)

These are ergonomic gaps in `CYRIUS_TARGET_EFI` mode, not bugs.
gnoboot ships fine without resolution. Both surfaced upstream:

- **No array-with-initializer syntax** — `var foo[N] = { 0x.., 0x.. };`
  rejected with `expected ';', got '='`. Cyrius supports
  `var s = "ascii";` for ASCII strings but not byte-array literals.
  Pattern for UTF-16LE buffers (UEFI CHAR16*) and EFI GUIDs:
  declare uninitialized `var buf[N];` and `store8(&buf + i, byte)`
  at runtime *inside a fn body*, OR embed the bytes inline in an
  `asm { ... }` block and reference via `lea rdx, [rip + N]`.
  *Filed upstream:* `cyrius/docs/development/issues/2026-05-13-gnoboot-byte-array-literal.md`.
- **Cyrius internal fn-call ABI under `_TARGET_EFI_APPLICATION` is
  MS x64**, not SysV. Verified via objdump: callee prologue saves
  RCX/RDX (not RDI/RSI) into local slots. This contradicts
  `cyrius/lib/fnptr.cyr`'s comment which documents SysV — that doc
  predates the TARGET_EFI work and is no longer accurate for this
  target. fncallN's asm doesn't have a TARGET_EFI branch either.
  *Filed upstream as part of:* `cyrius/docs/development/issues/2026-05-13-gnoboot-efi-main-convention.md`.
- **No `fn efi_main(handle, st)` entry convention.** Cyrius has the
  `fn main(); var r = main(); syscall(SYS_EXIT, r);` Linux/macOS
  pattern but no UEFI equivalent. Consumer hand-rolls a ~15-line
  asm trampoline (capture RCX/RDX → callee-saved R14/R15, get fn
  ptr via `var fp = &efi_main`, set MS x64 args, call, ret to
  firmware). Works but is delicate (small ordering bugs around
  top-level `var X = expr;` vs. `asm` interleaving cost a debugging
  cycle in Step 4a/Step 4 first attempt).
  *Filed upstream:* `cyrius/docs/development/issues/2026-05-13-gnoboot-efi-main-convention.md`.

### Verified entry-trampoline pattern (works under cyrius 5.11.49)

```cyrius
kernel;

fn efi_main(handle, st) {
    # ... normal cyrius. Inside a fn body, the agnos-shim
    # `var p = &g; asm { ... }` register-capture pattern works.
    return 0;
}

# Top-level: ~15 lines of asm hand off firmware entry to efi_main.
asm {
    0x49; 0x89; 0xCE;          # mov r14, rcx  ; save ImageHandle
    0x49; 0x89; 0xD7;          # mov r15, rdx  ; save SystemTable*
}
var fp = &efi_main;            # cyrius emits: rax = &efi_main
asm {
    0x4C; 0x89; 0xF1;          # mov rcx, r14  ; MS x64 arg 0
    0x4C; 0x89; 0xFA;          # mov rdx, r15  ; MS x64 arg 1
    0x48; 0x83; 0xEC; 0x08;    # sub rsp, 8    ; re-align stack
    0xFF; 0xD0;                # call rax
    0x48; 0x83; 0xC4; 0x08;    # add rsp, 8
    0x31; 0xC0;                # xor eax, eax  ; EFI_SUCCESS
    0xC3;                      # ret to firmware
}
```

R14/R15 are callee-saved in both SysV and MS x64, so they survive
across cyrius's `var fp = &efi_main` emit. The ABI inside the call
is MS x64 (cyrius's internal convention under TARGET_EFI).

### Pending for v0.1.0

- Step 4 — ESP file read: open SimpleFileSystem on the loaded image's
  device, traverse `\boot\agnos`, read into AllocatePages buffer.
- Step 5 — ELF64 parse + AllocatePages per PT_LOAD + memcpy/zero-fill.
- Step 6 — GetMemoryMap into the sovereign boot-info struct.
- Step 7 — sovereign struct build + ExitBootServices + jump to kernel
  entry with `RDI = &boot_info` (SysV ABI; magic `0x41474E4F = 'AGNO'`).
- Step 8 — AGNOS kernel shim swap MB2 → sovereign struct (cross-repo).
- Step 9 — end-to-end gnoboot → AGNOS kernel under QEMU OVMF (clean
  serial trace through scheduler + tier3 test "=== done ===").
- Step 12 — iron Attempt 5 on the NUC AMD (full re-provision; the
  closed-beta MVP gate).
