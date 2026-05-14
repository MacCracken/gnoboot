# Changelog

All notable changes to gnoboot will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **GOP framebuffer capture for Attempt 7 boot-canary** (2026-05-13).
  Attempt 6 on NUC AMD reproduced Attempt 5's symptom (step-7 line +
  blank + reset) — meaning the BSS-zero and EfiLoaderCode fixes below
  ran on iron and didn't change the outcome. Both highest-confidence
  hypotheses are ruled out; remaining hypotheses (inherited PT W^X,
  GDT divergence, CR0/CR4 state) can't be bisected without visibility
  into kernel-side execution, and no serial cable is yet attached.
  GOP capture lets the kernel's first instruction paint a visible
  canary stripe — see agnos `boot_shim.cyr` ELF64 path.

  Implementation: `LocateProtocol(EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID)`
  pre-EBS (Boot Service; must run before Step 12 `GetMemoryMap`
  refresh because any firmware call invalidates the map key).
  Copies `fb_phys`, `fb_pitch = ppl × 4`, `fb_width`, `fb_height`,
  `fb_pixel_format` from `gop->Mode` into inlined boot_info fields
  at offsets 0x48-0x5C. Pointers go dead post-EBS but the framebuffer
  physical base + geometry stay valid for the kernel's lifetime.
  Failure mode benign: if no GOP (text-mode/headless firmware),
  `fb_phys = 0` and the agnos canary's `JZ` skips the paint.

  Boot-info struct grows 80 → 112 bytes; version field bumps 1 → 2.
  Path-c doc § *Handoff protocol* updated to reflect the move from
  tag-stream (type=1) to inlined fields. Kernel walkers MUST NOT
  expect a framebuffer tag in the stream from v2 onward.

### Fixed

- **Iron-only triple-fault post-EBS** (gnoboot's first iron run —
  Attempt 5 / NUC AMD, 2026-05-13). Display showed "gnoboot 0.1 step 7:
  Jumping to kernel..." (cosmetically on the same line as the firmware
  splash because the splash didn't `\r\n`-terminate), then blank screen
  + reset. QEMU OVMF still booted the kernel through 17 init checkpoints
  to `Activating scheduler...` — divergence isolated to two gnoboot
  assumptions that held under OVMF but not under AMD Zen UEFI:
  1. **BSS gap not zeroed.** `main.cyr` read only `p_filesz` bytes
     into `p_paddr` and never zeroed `[p_filesz, p_memsz)` (64 KB for
     agnos 1.30.0). UEFI 2.x § 7.2 states `AllocatePages` returns
     undefined memory contents; QEMU OVMF happened to return zeroes,
     real firmware leaves POST/EFI scratch. Kernel `.bss` globals read
     garbage on iron, triple-fault at first reference. Fix: byte-loop
     `store8(addr, 0)` over the gap right after the segment read and
     ELF-magic verify. No new stdlib dep (gnoboot stays `[deps] stdlib = []`).
  2. **MemoryType 2 (EfiLoaderData) → 1 (EfiLoaderCode).** Strict-W^X
     firmware NX-marks LoaderData pages — jump to 0x1000A8 in a
     LoaderData page faults silently on iron; OVMF executes from
     LoaderData regardless. EfiLoaderCode tells firmware "this is
     executable" so NX stays clear in the inherited post-EBS page
     tables. One-byte change at the `bs->AllocatePages` call.

  Both fixes shipped in Attempt 6 — no improvement on iron (same
  symptom as Attempt 5). Hypotheses #1 and #2 ruled out; see *Added*
  above for the next bisection step.
  `tests/ovmf_smoke.sh` still PASS on QEMU OVMF (kernel reaches
  `Activating scheduler...`).
  Diagnosis logged in `agnosticos/docs/development/iron-boot-testing-log.md`
  § *Attempt 5* and § *Attempt 6*.


## [0.1.0] — 2026-05-13

First gnoboot release. AGNOS sovereign UEFI bootloader, Cyrius-native,
replaces GRUB on the boot path. Loads the AGNOS kernel from the ESP,
builds a sovereign boot-info struct, calls `ExitBootServices`, jumps
to kernel entry with `RDI = &boot_info`.

Verified end-to-end on QEMU OVMF: gnoboot delivers the AGNOS kernel
through its boot_shim into kernel-side init (banner + 9 further
init lines through `Page tables: 1024MB mapped` print post-EBS).
Iron Attempt 5 on the NUC AMD is the remaining validation pass.

Brought forward to MVP-critical 2026-05-13 after GRUB's multiboot2-EFI
relocator was found to write to its own `.text` and fault under
modern strict-W^X UEFI (see `agnosticos/docs/development/iron-boot-testing-log.md`
§ *Diagnosis 2 — 2026-05-13 GRUB relocator W^X* for the forensic
trail and `agnosticos/docs/development/path-c-sovereign-uefi.md` for
the plan).

### Added

- UEFI Application entry via cyrius 5.11.53's `fn efi_main(handle, st)`
  convention. Cyrius's auto-trampoline at `.text+0x339` saves the
  firmware-supplied `RCX` (ImageHandle) and `RDX` (SystemTable) into
  callee-saved `R14`/`R15`, runs gvar inits, restores into RCX/RDX,
  and calls `efi_main` with MS x64 ABI.
- ESP file access via `bs->HandleProtocol(handle, &LI_GUID)` →
  `bs->HandleProtocol(LI->DeviceHandle, &SFS_GUID)` →
  `sfs->OpenVolume` → `root->Open("\boot\agnos", READ, 0)` →
  `file->Read`. All five firmware calls via `lib/fnptr.cyr`'s
  MS-x64 `fncallN` branches (which fire under
  `CYRIUS_TARGET_EFI=1` via the v5.11.52 TARGET_WIN co-predefine).
- ELF64 kernel load: read 64-byte header, parse `e_phoff`, read
  56-byte PT_LOAD program header, `bs->AllocatePages(AllocateAddress,
  EfiLoaderData, pages, &p_paddr)` at the kernel's fixed
  `p_paddr = 0x100000`, `file->Read(file, &filesz, p_paddr)` writes
  segment data directly to physical memory. ELF-magic read-back
  verifies the load.
- Sovereign boot-info struct (80 bytes, layout in
  `agnosticos/docs/development/path-c-sovereign-uefi.md` § Handoff):
  magic `0x41474E4F ('AGNO')`, version 1, struct_size 80, memmap
  pointer/count/entsize, EFI SystemTable pointer, END tag at
  offset `0x48`. Built statically with a byte-array literal
  (cyrius 5.11.51) plus runtime `store32`/`store64` fills.
- `bs->GetMemoryMap` × 2 (informational + fresh-key right before
  EBS) into a 16 KB cyrius global buffer. The second call's
  `mm_key` is what `ExitBootServices(handle, mm_key)` requires.
- `bs->ExitBootServices(handle, mm_key)` — point of no return.
  After EBS, ConOut is gone; any further diagnostic is via the
  kernel's own COM1 UART output captured by QEMU `-serial stdio`.
- Inline-asm jump to kernel entry at `0x1000A8` with
  `RDI = &boot_info` (SysV arg 0): `mov rdi, rax; mov eax, 0x1000A8;
  jmp rax`. Cyrius's `var p = &boot_info` emits the
  `movabs rax, &boot_info` immediately before, leaving the
  destination in RAX for the asm.

### Tooling

- `tests/verify_pe.sh` — fast structural gate. Verifies DOS magic
  at 0x00, PE signature at 0x40, COFF Characteristics 0x0022 (no
  RELOCS_STRIPPED) at 0x56, Subsystem 0x000A (EFI_APPLICATION) at
  0x9C, DllCharacteristics NX_COMPAT bit set at 0x9E. Runs without
  QEMU.
- `tests/ovmf_smoke.sh` — runtime end-to-end gate. Builds a 64 MB
  GPT disk with ESP at 1 MiB, copies `build/BOOTX64.EFI` to
  `\EFI\BOOT\BOOTX64.EFI` and (optionally) the agnos kernel build
  to `\boot\agnos`, boots under qemu-system-x86_64 + OVMF, asserts
  the expected banner appears on the firmware ConOut serial.
  Cross-distro OVMF path probing (Arch `edk2-ovmf` + Ubuntu
  `ovmf`); graceful SKIP if `qemu-system-x86_64`, `parted`,
  `mtools`, or OVMF firmware files are missing.
- `.github/workflows/ci.yml` — installs cyrius (canonical
  `install.sh` + post-install smoke per the agnos pattern), builds
  with `CYRIUS_TARGET_EFI=1`, runs both gates on `ubuntu-latest`
  with `ovmf parted mtools qemu-system-x86` apt-installed, uploads
  `BOOTX64.EFI` as a build artifact.
- `.github/workflows/release.yml` — triggered on `v?X.Y.Z` tags.
  CI gate first; then version-verifies `VERSION` against the tag,
  builds, structural-gates, stages release artifacts
  (`BOOTX64.EFI` + `gnoboot-X.Y.Z-x86_64-efi.efi` + `SHA256SUMS`),
  publishes to a GitHub release with auto-generated notes via
  `softprops/action-gh-release@v2`.

### Cross-repo dependencies

- **cyrius 5.11.53** — pinned in `cyrius.cyml`. v0.1.0 specifically
  needs:
    - **5.11.51** — byte-array literal `var foo[N] = { 0x.., ... };`
    - **5.11.52** — `fn efi_main(handle, st)` convention + cyrius
      auto-predefines `CYRIUS_TARGET_WIN` alongside
      `CYRIUS_TARGET_EFI` (so `lib/fnptr.cyr`'s MS-x64 fncallN
      branches fire under TARGET_EFI).
    - **5.11.53** — hotfix for v5.11.52's entry-save REX prefix
      (was emitting `mov rsi, r9; mov rdi, r10` instead of
      `mov r14, rcx; mov r15, rdx` — gnoboot agent caught the bug
      hours after 5.11.52 ship; fix landed same-day).
- **agnos 1.30.0** — pairs with gnoboot v0.1.0. Kernel ABI break:
  entry contract switched from multiboot2's `RBX = MBI ptr` to
  sovereign-struct's `RDI = &boot_info`. The 3-byte asm change is
  in `kernel/arch/x86_64/mbi.cyr` (`mov [rax], rbx` →
  `mov [rax], rdi`); the kernel still just stashes the pointer,
  doesn't yet read it.

### Upstream issues filed

Gnoboot's bring-up surfaced four cyrius issues, three of which
landed in the v5.11.51–v5.11.53 cycle:

1. **UEFI Application emit mode** (filed → cyrius 5.11.49).
   Adds `_TARGET_EFI_APPLICATION` flag gated by
   `CYRIUS_TARGET_EFI=1`: PE32+ with subsystem 0xA, no Win32
   imports, populated `.reloc`, RELOCS_STRIPPED cleared.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-uefi-application-emit.md`.
2. **Byte-array literal syntax** (filed → cyrius 5.11.51).
   `var foo[N] = { 0x.., 0x.., ... };` for compile-time-known
   UTF-16LE strings, EFI GUIDs, sovereign-struct static init.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-byte-array-literal.md`.
3. **`fn efi_main(handle, st)` convention** (filed → cyrius 5.11.52).
   Auto-emits the firmware-entry trampoline. Cyrius scans `fn_names`
   for `efi_main\0` and emits save / restore / call sequence around
   the standard gvar-inits flow.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-efi-main-convention.md`.
4. **cyrius-lsp byte-array-literal recognition** (filed; pending,
   candidate for 5.11.54+). LSP still emits a parse-error
   diagnostic on `var foo[N] = { ... }` even though `cc5` accepts
   it — likely the LSP wasn't rebuilt against the v5.11.51
   frontend. Diagnostic noise only; doesn't affect builds.
   `cyrius/docs/development/issues/2026-05-13-gnoboot-lsp-byte-array-literal.md`.

### Known limitations

- **AGNOS kernel stalls past `Page tables: 1024MB mapped`** under
  the UEFI + gnoboot boot path. Under the legacy
  `qemu-system-x86_64 -kernel` path the kernel reached
  `Memory isolation: PASS` / `Userland exec complete` /
  `KASLR: pmm_next_free=N`. The two paths differ in pre-handoff
  environment (UEFI's GDT + identity-mapped page tables + NX bits
  vs. the kernel's own boot-shim setup under `-kernel`). The
  kernel-side init survives 10 checkpoints — the stall is post-
  page-tables. Not a gnoboot bug: handoff is verified correct
  (banner + 9 lines print *after* `ExitBootServices`). Tracked in
  `agnos/docs/development/state.md` § *Open investigation — kernel
  hang post-page-tables under UEFI+gnoboot*; expected to land in
  the next agnos sub-arc.
- **Iron Attempt 5 (NUC AMD) not yet exercised.** v0.1.0 is verified
  on QEMU OVMF emulation only. The iron test path is full
  `scripts/install-usb.sh` re-provision (via the agnosticos repo)
  + NUC AMD reboot. Tracked in
  `agnosticos/docs/development/iron-boot-testing-log.md`.
- **Cyrius-lsp diagnostic noise** on every save of `src/main.cyr`:
  `[Line 1:1] expected ';', got '='`. LSP is misreading the
  byte-array literal syntax; build is unaffected. Pending upstream
  rebuild (see *Upstream issues filed* #4).

### Development notes

A handful of bisection findings that drove the source's current
shape — useful for the next gnoboot contributor; not strict release
content.

- **Top-level `kernel;` mode emit order**: `var X = expr;` at the
  top level of a `kernel;` source is a *global with deferred
  initializer*, not an inline statement. Cyrius emits intervening
  `asm` blocks BEFORE the `&expr` lea, so the agnos-shim
  `var p = &foo; asm { mov [rax], rdx }` register-capture pattern
  silently fails at top level (RAX is junk; capture writes to
  random memory). The pattern works **inside a fn body** — locals
  ARE inline. gnoboot's "Step 4a probe" originally claimed PASS
  from this pattern; Step 4's disassembly later revealed the
  capture was a no-op and the post-capture print only worked
  because it used firmware-preserved RDX directly. After the
  cyrius 5.11.52 `fn efi_main` convention landed, the pattern
  became irrelevant — cyrius auto-emits the entry trampoline.
- **Cyrius internal fn-call ABI under `_TARGET_EFI_APPLICATION` is
  MS x64**, not SysV — verified via `objdump`. Callee prologue
  saves RCX/RDX (not RDI/RSI) to local slots. This contradicts
  `lib/fnptr.cyr`'s longstanding SysV comment, which predates the
  TARGET_EFI work. Under v5.11.52+ cyrius predefines
  `CYRIUS_TARGET_WIN` alongside `CYRIUS_TARGET_EFI` so the
  TARGET_WIN MS-x64 branches in `fnptr.cyr` fire — `fncallN` does
  the right thing under TARGET_EFI without per-target plumbing.
- **Byte-array literal `[N]` capacity** is `N × 8` bytes (cyrius's
  array-slot semantic). For UTF-16LE messages, `N = ceil((chars+1)*2 / 8)`.
  Cyrius reports overflow errors with a line number that points
  *near* — sometimes one or two lines before — the first
  overflowing array; not always the array itself. Two early
  overflows (`msg_li_fail` at 18 B in N=2=16 cap, `msg_sfs_fail`
  at 20 B) were misread as a different array failing because the
  reported line was a blank line. Re-look at the next overflow
  encountered.
- **OVMF requires GPT-disk-with-ESP** for the
  `\EFI\BOOT\BOOTX64.EFI` removable-boot path to resolve. A raw
  FAT image gets `BdsDxe: failed to load Boot0002: Not Found`.
  `tests/ovmf_smoke.sh` builds the canonical layout: 64 MB image
  + GPT label + single FAT32 ESP partition at 1 MiB + `esp on`
  flag.
- **`AllocatePages` at `AllocateAddress = 0x100000`** works under
  OVMF (firmware reserves below 1 MB but not at the 1 MB mark
  itself). `EfiLoaderData` MemoryType lets us write to the
  allocated pages during boot services time; W^X "no-execute"
  enforcement only bites at execution-time (didn't affect our
  load — and didn't affect the post-EBS jump to 0x1000A8 either,
  since the kernel ran far enough to print 10 init lines).
- **`ExitBootServices` map-key invalidation**: any firmware
  service call (including `efi_print` via ConOut) between
  `GetMemoryMap` and `ExitBootServices` invalidates the
  `mm_key`. gnoboot calls `GetMemoryMap` once informationally
  early, then re-calls it immediately before `ExitBootServices`
  with no intervening firmware calls. The fresh key passes.
