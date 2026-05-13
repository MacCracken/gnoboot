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

### Known cyrius constraints (informed Step 4 design)

- **No array-with-initializer syntax** — `var foo[N] = { 0x.., 0x.. };`
  is rejected with `expected ';', got '='`. Cyrius supports
  `var s = "ascii";` for ASCII strings but not byte-array literals.
  Pattern for UTF-16LE buffers (UEFI CHAR16*): declare uninitialized
  `var buf[N];` and `store8(&buf + i, byte)` at runtime *inside a fn*,
  OR embed the bytes inline in an `asm { ... }` block and reference
  via `lea rdx, [rip + N]`.
- **Cyrius internal ABI is SysV (RDI/RSI/RDX/RCX/R8/R9)**, even
  under `_TARGET_PE` / `_TARGET_EFI_APPLICATION`. The MS x64 ABI
  work is only for the entry boundary. Calls to firmware function
  pointers (UEFI's MS x64 ABI: RCX/RDX/R8/R9 + 32-byte shadow space
  + 16-byte stack alignment) need an inline-asm trampoline at every
  firmware-call site. Source: `cyrius/lib/fnptr.cyr` comment block.
- **At top-level `kernel;` mode, `var X = expr;` is a global with
  deferred initializer**, not a local — cyrius emits intervening
  `asm` blocks BEFORE the `&expr` lea, so the agnos shim's
  `var p = &foo; asm { mov [rax], ... }` register-capture pattern
  DOES NOT WORK at top level. (Caught the hard way: Step 4a "passed"
  but the capture was a no-op; the OK print was firmware-RDX-direct.
  Step 4's first attempt with the same pattern got
  `HandleProtocol = FAIL` because the handle global got garbage.)
  Workarounds: (a) move the capture into a fn body — then `var p`
  is a real local and the pattern works; (b) keep everything in one
  pure-asm block at top level and use the stack for writable scratch
  (current Step 4 shape).

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
