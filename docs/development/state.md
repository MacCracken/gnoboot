# gnoboot — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).
>
> **Last refresh**: 2026-11-01 (**v0.8.3 cut** — ET_DYN / KASLR runtime coverage: `tests/kaslr.sh` and `tests/build_pie_agnos.sh`, a release-cut gate. One image byte moved. Found gnoboot runs `rdrand` without a CPUID check. All local gates green; awaiting user tag, not iron-tested). Prior: 2026-11-01 (**v0.8.2 cut** — real boot gates in CI: OVMF `_4M` paths, a pinned agnos kernel, SKIP exits 77, and a banner-vs-`VERSION` check. One image byte moved. All local gates green plus a runner simulation; awaiting user tag and the first real CI run, not iron-tested). Prior: 2026-11-01 (**v0.8.1 cut** — pin `6.7.9` → `6.7.18`, **measured inert**: the compiler-only build is byte-identical to 0.8.0; the version bump is one byte. All local gates green; awaiting user tag, not iron-tested). Prior: 2026-11-01 (**v0.8.0 cut** — pin `6.6.20` → `6.7.9`, **measured inert**: the compiler-only build is byte-identical to 0.7.3; the version bump is two bytes. All local gates green; awaiting user tag, not iron-tested). Prior: 2026-11-01 (**v0.7.3 cut** — pin `6.6.2` → `6.6.20`, **not inert**: image 37,376 → 35,328 bytes; version bump itself one byte at `0x401A`. Fixed the banner 0.7.2 left at `v0.7.1`. `stdlib = ["fnptr"]` commented out to work around a cyrius bug. All local gates green; awaiting user tag, not iron-tested. Found CI's boot gates SKIP). Prior: 2026-09-11 (**v0.7.2 cut** — pin `6.5.36` → `6.6.2`; this file was not refreshed at that cut, the entry below was backfilled at v0.7.3). Prior: 2026-08-29 (**v0.7.1 cut** — pin `6.5.35` → `6.5.36` (**measured: zero emitted bytes changed**; `lib/fnptr.cyr` byte-identical between the two snapshots, `fncall2` body included), roadmap **M4** shipped as [`docs/standards/handoff-protocol.md`](../standards/handoff-protocol.md), and the one live bug writing that spec exposed: **`fb_mode_chosen` at `0x6C` overlapped `fb_size`'s u64 at `0x68` and was destroyed on every boot since v0.6.1** — always read `0`. Relocated to `0x78`; struct grew 120 → 128 bytes, `version` unchanged at 2. All four gates green. Awaiting user tag). Prior: 2026-08-29 (**v0.7.0 cut** — *ELF-load hardening*, closing audit F1–F4/F6/F7/F9 and merging M5+M7; `malformed_kernel.sh` 18/18 and `multi_ptload.sh` PASS). Prior: 2026-08-29 (**pre-1.0 security audit** — [`docs/audit/2026-08-29-audit.md`](../audit/2026-08-29-audit.md), 10 findings / 9 verified-sound; no code changed in that pass). Prior: 2026-08-26 (**v0.6.2 cut** — toolchain pin-bump patch release: `cyrius.cyml` pin `6.2.44` → `6.5.35`, `lib/fnptr.cyr` re-vendored from the matching stdlib snapshot (comment-only), banner `v0.6.1` → `v0.6.2`. Measured: pre- and post-bump trees built under the same compiler differ in **exactly one byte** — the banner's patch digit. Structural + OVMF gates green; handoff sequence re-disassembled because 6.5.35 is a regalloc release; **tagged `0.6.2` at `741e935`**). 2026-08-03 (**v0.6.1 cut** — native-resolution GOP mode selection via `QueryMode`/`SetMode`, `boot_info` 0x6C `fb_mode_chosen`, and the `ovmf_smoke.sh` `EXPECT` fix that made the banner gate derive from `VERSION`). 2026-06-27 (**v0.6.0 cut** — full-binary KASLR / ET_DYN PIE kernel load, `boot_info` 0x70 `kernel_base`, pin `6.2.24` → `6.2.44`). 2026-06-19 (**v0.5.1 cut** — pin-bump patch release `6.0.47` → `6.2.24`). 2026-06-03 (**v0.5.0 cut** — the `boot_info` feature-fill release: `initramfs_phys`/`size` + `cmdline_phys` + `acpi_rsdp_phys` populated pre-EBS, all optional + benign-on-failure). 2026-06-01 (Open-section reconcile to the agnos 1.40.x reality). 2026-05-28 (v0.4.3 — pin bump to 6.0.14).

## Version

**0.8.3** — cut 2026-11-01 (awaiting user tag). ET_DYN / KASLR runtime coverage. No
bootloader code changed and no ABI change: one image byte, `0x401A`.

The PIE branch now has real results (§ Verified), and `tests/kaslr.sh` guards it at
release cuts. **⚠ Running it found one bug:** gnoboot executes `rdrand` without
checking CPUID, so a PIE load on a CPU without RDRAND faults with `#UD`. Nothing
shipping hits it. See § Open.

Prior — **0.8.2** — cut 2026-11-01, tagged `0.8.2`. Real boot gates in CI, proven by
a real run (§ CI / Release). No bootloader code changed and no ABI change.

**⚠ The thing worth knowing about that cut: fetching a kernel alone would have made
things worse.** A SKIP inside `ovmf_smoke.sh` exited 0, and `malformed_kernel.sh`
counted that as a pass, so a kernel present with QEMU absent printed `gate: PASS`
with nothing booted. SKIP now exits **77** everywhere, which fails a CI step on its
own.

Prior — **0.8.1** — cut 2026-11-01, tagged `0.8.1`. Pin `6.7.9` → `6.7.18`, the
latest release, measured inert against 0.8.0. No ABI change.

Prior — **0.8.0** — cut 2026-11-01, tagged `0.8.0`. Pin `6.6.20` → `6.7.9`, measured
inert against 0.7.3. No ABI change.

Prior — **0.7.3** — cut 2026-11-01, tagged `0.7.3`. Toolchain pin bump plus the
banner fix 0.7.2 missed. No ABI change.

**Pin `6.6.2` → `6.6.20`, and this one is not inert.** The image drops
37,376 → 35,328 bytes (byte lists baked, 6.6.16), the entry sequence changes
(UEFI alignment, 6.6.5), and `fncall2` goes dead (bare-statement lowering, 6.6.5).
The version bump alone is one byte, `0x401A`. See § Binary.

**⚠ Three things worth knowing about this cut:**

1. **The `0.7.2` binary prints `v0.7.1`** and fails `ovmf_smoke.sh`. It boots fine;
   only the string was wrong.
2. **`stdlib = ["fnptr"]` is commented out**, working around a cyrius bug still
   present at 6.7.18. See § Dependencies, and § Toolchain before touching `lib/`.
3. **CI runs no boot gate.** See § Open. That is how (1) shipped green.

Prior — **0.7.2** — cut 2026-09-11, tagged `0.7.2`. Pin `6.5.36` → `6.6.2`, plus
test-harness rework. The banner was not bumped.

Prior — **0.7.1** — cut 2026-08-29 (never tagged). Pin bump + **M4** + the bug
M4 found.

**Pin `6.5.35` → `6.5.36`, measured at zero bytes.** `lib/fnptr.cyr` is
byte-identical between the two stdlib snapshots — including the live `fncall2`
body the three statement-position `SetMode` calls still reach — so the re-vendor
is provably inert, and building pre- and post-bump under the same compiler gives
identical binaries. The version bump then contributes exactly one byte (`0x3CE2`,
the banner's patch digit). The pin, `~/.cyrius/current`, and latest-published all
agree again; no drift warning.

**M4 shipped**: [`docs/standards/handoff-protocol.md`](../standards/handoff-protocol.md)
— the authoritative contract. Register convention and machine state at entry;
every field with type / offset / absent-value / introducing version; the
guarantees about the loaded kernel image; compatibility rules; required consumer
validation; memory-lifetime ownership post-EBS; per-field consumer status against
agnos 1.56.52; errata. **Audit F5 is settled: `boot_info` is flat and
fixed-offset, there is no tag stream and there will not be one**, with
append-only growth and `struct_size` as the sole authority.

**⚠ The thing worth knowing about this cut: writing the spec found a field that
had never worked.** `fb_mode_chosen` was a `u32` at `0x6C`; `fb_size` is a `u64`
at `0x68` covering `0x68`–`0x6F`. They **overlapped**, and the `0x6C` store ran
before the `0x68` store — so the `u64` landed last and destroyed the mode on
every boot since v0.6.1. It read the high half of `FrameBufferSize`: `0` for any
framebuffer under 4 GB, i.e. always.

That is the field the **AMD-Zen scanout question** depends on — the whole point
of `fb_mode_chosen` is separating *"no larger mode was offered"* from *"gnoboot
picked one and the firmware refused"*, and it would have produced a **false
positive on the next archaemenid burn**. Reordering was not available: putting
`best_mode` in `fb_size`'s upper half makes agnos's `load64(bi + 0x68)` report a
multi-gigabyte framebuffer to its WC remap. Fixed by separating them —
`fb_mode_chosen` → `0x78`, struct 120 → **128 bytes**, `struct_size` `0x78` →
`0x80`, `version` **unchanged at 2** because the growth is append-only. It lands
inside agnos's existing 128-byte `boot_info_copy`, and incidentally removes the
8-byte over-read that copy always performed.

The general lesson, worth keeping: **the overlap was invisible in a comment block
listing offsets in the order fields were added, and obvious in a table sorted by
address.** That is what the spec bought.

Prior — **0.7.0** — cut 2026-08-29 (awaiting user tag). **ELF-load hardening** —
the release the 2026-08-29 audit scoped. Closes findings F1–F4, F6, F7, F9
and merges roadmap **M5** (multi-`PT_LOAD`) with **M7** (validation hooks),
which the audit found to be the same twenty lines.

**Not an ABI change.** Magic `'AGNO'`, struct version `2`, `struct_size 0x78`
and `RDI = &boot_info` are untouched. The one handoff-visible addition is
`flags` **bit 2 (`kaslr_no_entropy`)**, which is additive — a v2 reader that
ignores it behaves exactly as before.

What changed, in one line each:

- **The ELF check is now a gate.** Was one byte (`0x7F`); anything past it drove
  `AllocatePages` and `Read` from arbitrary u64s. Now: 4 magic bytes, `EI_CLASS`,
  `EI_DATA`, `e_type`, `e_machine`, `e_phentsize` — all before `e_phoff` is used.
- **All `PT_LOAD` segments load.** Was `phdr[0]` only, so a 2-segment kernel was
  *silently under-loaded* and a `PT_PHDR`-first kernel failed outright. Now one
  bounded read of the whole table, validate-everything-then-allocate, one
  contiguous span allocation, per-segment copy + BSS zero.
- **Short reads are caught.** UEFI 2.10 §13.5.1 permits a partial `Read` that
  still returns `EFI_SUCCESS`; a truncated kernel used to load "successfully"
  into undefined memory (UEFI 2.x §7.2) and get jumped into.
- **Segment fields are bounded** against a `GetInfo`-derived file size, with a
  256 MB cap (the kernel's own per-proc-CR3 identity ceiling) that makes the page
  arithmetic provably wrap-free rather than merely defended.
- **KASLR fails loudly.** `rdrand_u64` retries 10× on CF=0 and sets flags bit 2 on
  exhaustion. Previously all 16 re-rolls called the same failing instruction and
  returned the same value — a fixed base indistinguishable from a real slide.
- **Firmware counts bounded consistently** — GOP `MaxMode`, null `ConfigurationTable`,
  zero `DescriptorSize` (the ACPI walk already capped at 256).

The thing worth knowing about this cut: **the hardening is tested, not asserted.**
`tests/malformed_kernel.sh` boots 18 deliberately-corrupted kernels under OVMF and
asserts each one's specific failure code (18/18); `tests/multi_ptload.sh` splits the
real kernel's `PT_LOAD` in two and proves it boots equivalently. Before those, every
new check was unexercised code — and the two existing gates would have stayed green
through a regression that deleted any of them.

Prior — **0.6.2** — cut 2026-08-26, **tagged** (`0.6.2` → `741e935`). Toolchain **pin-bump
patch** release: `cyrius.cyml` pin `6.2.44` → `6.5.35`, `lib/fnptr.cyr`
re-vendored from the 6.5.35 stdlib snapshot, and the banner version
string `v0.6.1` → `v0.6.2`. **No gnoboot source behavior change** beyond
the banner — boot path, handoff contract (magic `'AGNO'`, struct version
`2`, `struct_size 0x78`), and ABI are identical to v0.6.1.

The one thing worth knowing about this cut: it was **measured, not
assumed**. Building the pre-bump and post-bump trees under the same
compiler yields binaries differing in exactly one byte — file offset
`0x2CE9`, the `imm8` of `mov byte [rcx+0x1a], 0x32`, i.e. the banner's
patch digit. The `lib/fnptr.cyr` refresh contributes zero emitted bytes,
so the re-vendor is provably inert.

Prior — **0.6.1** (cut 2026-08-03): **native-resolution GOP mode
selection**. `efi_main` enumerates every mode via `QueryMode` and
`SetMode`s the largest `width * height` whose `PixelFormat` is 0 (RGB) or
1 (BGR); formats 2 (BitMask) and 3 (BltOnly) are refused because the
kernel writes the framebuffer directly. Fail-safe by construction —
`best_mode` seeds from `cur_mode`, and a non-zero `SetMode` restores.
Added `boot_info` **0x6C (u32) `fb_mode_chosen`** so a burn can tell
"no larger mode existed" from "SetMode refused the one we picked". Also
fixed `tests/ovmf_smoke.sh`, whose `EXPECT` had been a hardcoded
`v0.5.1` while `VERSION` read `0.6.0` — the banner gate had been failing
for an entire release. `EXPECT` now derives from `VERSION`.

Prior — **0.6.0** (cut 2026-06-27): **full-binary KASLR**, relocatable
PIE-kernel load (pairs with agnos 1.47.4). For an ET_DYN kernel gnoboot
picks an RDRAND-chosen, 2 MB-aligned base in [32 MB, 254 MB) and
`AllocatePages(AllocateAddress)` there, re-rolling up to 16× before
falling back to the fixed `0x100000`; the handoff jump is computed from
the ELF header (`load_base + e_entry`) instead of the hardcoded
`0x1000A8`; the chosen base goes to `boot_info+0x70`. A non-PIE ET_EXEC
kernel loads at its `p_paddr` and jumps to its absolute entry exactly as
before. Advanced the pin `6.2.24` → `6.2.44` alongside the agnos-side
ET_DYN work (see § Toolchain — that codegen requirement is on the
toolchain that builds agnos, not on gnoboot's own PE32+ emit).

Prior — **0.5.0** (cut 2026-06-03): the **boot_info feature-fill**
release: three reserved fields that passed `0` since v0.1.0 are now
populated pre-ExitBootServices, all OPTIONAL + benign-on-failure (a
normal boot with no extra ESP files is byte-for-byte unaffected). No ABI
change.
- `initramfs_phys` (0x10) / `initramfs_size` (0x18) ← `\boot\initramfs`
  (format-NEUTRAL path; kernel owns the format, sovereign INDR not Linux
  cpio.gz). The ISO live-`.iso` RAM-root gate.
- `cmdline_phys` (0x20) ← `\boot\cmdline` (forward-compat; no consumer yet).
- `acpi_rsdp_phys` (0x38) ← EFI Configuration Table walk (ACPI 2.0 GUID
  preferred, 1.0 fallback). Unblocks ACPI under UEFI.

## Toolchain

- **Cyrius pin**: `6.7.18` (in `cyrius.cyml [package].cyrius`) — advanced from
  `6.7.9` at the **v0.8.1** cut. Pin, `~/.cyrius/current` and latest-published
  all agree. **Measured inert**: zero bytes differ from the 0.8.0 image before
  the version bump.
- **Prior pin** `6.7.9` — advanced from `6.6.20` at the **v0.8.0** cut. **Measured
  inert** against the 0.7.3 image the same way.
- **Prior pin** `6.6.20` — advanced from `6.6.2` at the **v0.7.3** cut. **Not
  measured inert**: 6.6.5 and 6.6.16 both change the emitted image (see § Binary).
- **Prior pin** `6.5.36` — advanced from
  `6.5.35` at the **v0.7.1** cut. **Measured inert**: `lib/fnptr.cyr` is
  byte-identical between the 6.5.35 and 6.5.36 snapshots (`fncall2`'s live body
  included), and pre-/post-bump binaries differ in zero bytes. Pin,
  `~/.cyrius/current` and latest-published agree; no drift warning. History
  below describes `6.5.35`, which was advanced
  from `6.2.44` at the v0.6.2 cut (and `6.2.24` → `6.2.44` at v0.6.0,
  which was never recorded here). `6.5.35` is the latest **released**
  cyrius (published 2026-08-22; the `install.sh` release asset resolves,
  so CI can install it). At the v0.6.2 cut it was also the local wrapper
  version — the first time since v0.5.1 that pin, `~/.cyrius/current`, and
  latest-published all agreed. **Drift has since reappeared** (observed
  2026-08-29: local `cycc` is `6.5.36`, pin is `6.5.35`), so the benign
  pin-drift warning rides every build again. Harmless — nothing in 6.5.36
  is a gnoboot dependency — but it is back.
- Required cyrius features:
    - 5.11.49 — `_TARGET_EFI_APPLICATION` PE32+ EFI emit mode
    - 5.11.51 — byte-array literal `var foo[N] = { 0x.., 0x.., ... };`
    - 5.11.52 — `fn efi_main(handle, st)` auto-trampoline + lib/fnptr.cyr
      TARGET_WIN branches under TARGET_EFI
    - 5.11.53 — entry-save REX prefix hotfix (gnoboot agent filed)
    - 6.0.46 — `CYRIUS_TARGET_EFI ⇒ CYRIUS_TARGET_WIN` predefine implication
      restored (the v6.0.0 regression that emitted `ud2 ud2` at every `fncallN`
      site under EFI), locked behind two check.sh gates (`efi_fncall_probe.cyr`
      + `_efi_emit_gate` PE byte-scan). Issue archived cyrius-side.
    - 6.2.44 — pinned at v0.6.0 alongside the KASLR work. Note this is a
      **cross-repo** note, not a gnoboot build requirement: gnoboot emits
      PE32+ and never uses `EMITELF64_KERNEL`; the ET_DYN codegen requirement
      is on the toolchain that builds *agnos*. gnoboot only needs to load
      whatever ET_DYN image it is handed.
    - 6.5.17 — `fncall0..fncall8` lowered **in the compiler** as inline
      indirect calls instead of calls into `lib/fnptr.cyr`. Under
      `CYRIUS_TARGET_EFI=1` this takes the MS-x64 `ECALLPTR_PE` path
      (shadow space, 16-byte alignment, and the 6.4.43 fix leaving
      `r12`/`r14`/`r15` untouched). The vendored trampoline bodies still
      compile in — `FINDFN` must succeed — but are now uncalled.
    - 6.5.17 is the only 6.5-band entry gnoboot actually depends on. (An
      earlier draft of this file claimed 6.5.25's dep-resolver fix named
      gnoboot as an affected consumer — it does not. The cyrius CHANGELOG
      names gnoboot at **6.4.63**, in the `lib_freshness` check, and for the
      opposite reason: the check keys on `[package] name`, precisely so that
      downstream repos which also build from `src/main.cyr` — gnoboot among
      them — are not silently exempted from it.)
    - 6.6.5 — UEFI entry alignment. The landing parks the entry rsp
      (`lea r13,[rsp]`), seeds `sub rsp,8`, uses a `0x20` trampoline frame
      (was `0x28`), and returns with `mov rsp,r13; ret`. Also lowers
      bare-statement `fncallN`, which is what killed the last live `fncall2`.
    - 6.6.16 — byte lists are baked into the image instead of stored by code at
      entry; values hold from the first instruction. Drops 2 KB.
    - 6.6.20 — **a hard constraint, not a feature.** `fn fncall0..8` is refused
      outside an included file named `fnptr.cyr`. See § Dependencies for how
      that collides with gnoboot's manifest.

**Re-vendoring `lib/`** ⛔ **changed at v0.7.3.** `fnptr` is undeclared while the
cyrius bug in § Dependencies stands, and with nothing declared the usual verbs
are destructive:

- **Bare `cyrius lib sync` copies the whole 113-file snapshot** into the
  deliberately one-file `lib/`, because an empty declaration means "full".
- **`cyrius update` does the same from the wrong toolchain.** It ignores the pin
  and copies `~/.cyrius/current`'s snapshot (observed: 6.7.18 under a 6.6.20 pin),
  including over `lib/fnptr.cyr`. This is true with `fnptr` declared as well.
  Never run it here.

To re-vendor: bump `[package].cyrius` first, uncomment `stdlib = ["fnptr"]`, run
`cyrius lib sync --no-lock`, then re-comment the line. The pin must move first,
because sync vendors from the **manifest pin** and otherwise silently re-vendors
the old snapshot. Do not pass `--full`. A build run while the line is uncommented
writes a `cyrius.lock`; delete it, since the dep it pins is undeclared again.

## Binary

- **`build/BOOTX64.EFI`**: 35,328 bytes at v0.8.3, unchanged since v0.7.3 (37,376
  before that). The 2 KB drop was cyrius 6.6.16 baking byte lists into the image.
  The v0.8.3 version bump is **exactly one byte** against the same-compiler build:
  file offset `0x401A`, the banner's patch digit (`0x4016` is the minor digit). PE32+
  EFI Application, x86_64, subsystem 0x000A,
  `DllCharacteristics` 0x0140 = NX_COMPAT + DYNAMIC_BASE, `.reloc` populated.
- **`.rdata` is writable** (`0xC0000040`, R+W, no X) and holds gnoboot's globals
  despite the name, so `efi_fail`'s in-place patch of `msg_fail` still works
  now that the template is baked. `.text` stays R+X, not W.
- Since cyrius 6.6.5 the `fncallN` call sequences are **emitted inline at every
  firmware-call site**, the three bare-statement `SetMode` calls included (those
  were the holdouts from 6.5.17, which lowered expression position only). No
  direct `call` reaches the `lib/fnptr.cyr` bodies. **`lib/fnptr.cyr` is
  therefore no longer live code on the boot path**; it is needed only so
  `FINDFN` succeeds, which is what enables the lowering.
- The build's `note: 9 unreachable fns (1352 bytes)` covers all **nine**
  vendored bodies, `fncall0`..`fncall8`, per `CYRIUS_DCE_VERBOSE=1`. This is the
  transition this file previously told readers to watch for. If it ever reads
  fewer than 9, something started reaching a body again.
- **Entry**: cyrius e9 jmp prologue at `.text+0`, jumps to the landing, which
  parks the entry rsp in `r13`, seeds `sub rsp,8`, captures `RCX → R14` and
  `RDX → R15`, opens a `0x20` frame, then `call efi_main` (MS x64 ABI). A return
  goes through `mov rsp,r13; ret`.
- **Banner storage note** ⚠ reversed at v0.7.3. `var foo[N] = { ... }` byte
  lists are now a contiguous blob in `.rdata`: the banner is at file offset
  `0x4000`, `msg_fail` at `0x4050`, and `boot_info` at `0x41D0`. So the `AGNO`
  magic is **data**, not an immediate; searching a disassembly for `0x41474e4f`
  finds nothing. `tests/verify_pe.sh` checks the banner this way since v0.8.2,
  though the OVMF gate is still what proves it prints.

## Source

- `src/main.cyr` — single file, ~1,020 lines (740 before the v0.7.0
  hardening). UTF-16LE message constants (one `msg_pre` banner + one
  shared `msg_fail` template + **17** per-stage `code_*` codes — v0.7.0
  added `GI` / `PHN` / `SZ` / `SHR`), EFI GUIDs (LoadedImage + SimpleFileSystem
  + GraphicsOutput + FileInfo + ACPI 2.0/1.0), helpers `efi_print` /
  `efi_clear` / `efi_fail` / `load_esp_blob` / `guid_eq` / `rdrand_u64`,
  entry `fn efi_main(handle, st)`. Entry trampoline auto-emitted by cyrius.
- Two **hand-verified codegen idioms** live at the inline-asm boundary.
  cyrius skips register allocation for any fn whose body contains inline
  asm, which is what keeps them stable — both `efi_main` and `rdrand_u64`
  qualify. Re-verify by disassembly after any toolchain bump:
    - `rdrand_u64`: `var pout = &out;` must leave `&out` in RAX
      (`lea rax,[rbp-0x8]`) before the block. **v0.7.0 replaced the single
      `rdrand` with a 10× retry loop** (`mov r8,0xa` / `rdrand rcx` / `jb` /
      `dec r8` / `jne` / `xor rcx,rcx` / `mov [rax],rcx`) — re-disassembled at
      the cut, the lea-into-rax idiom holds across it and `r8` (caller-saved
      in both ABIs) is untouched by the fn's own prologue/epilogue.
    - `efi_main` tail: `var p = &boot_info;` → `movabs rax, &boot_info`,
      then asm `mov rdi, rax`, then `var jt = kernel_jump_target;` must be
      a plain `mov rax,[rbp-N]` that **does not touch RDI**, then asm
      `jmp rax`. Re-confirmed at the **v0.7.3** cut: `mov rdi,rax` →
      `mov rax,[rbp-0x198]` → `mov [rbp-0x3a0],rax` → `jmp rax`. The extra
      store is `jt`'s own stack slot — it writes the stack, never RDI.
    - `rdrand_u64` was re-confirmed at the same cut, unchanged. Since 6.6.5 the
      landing is a third thing to check: see **Entry** in § Binary.
- `var foo[N]` sizes are in **u64 slots** — `N` × 8 bytes, not `N` bytes.
  `msg_pre[10]` = 80 bytes and the banner uses all 80. A version string
  one character longer (e.g. `0.6.9` → `0.6.10`) needs `N = 11`.

## Tests

- `tests/verify_pe.sh` — fast structural gate (5 PE header fields plus,
  since v0.8.2, the banner against `VERSION`). Asserts DOS magic, PE sig,
  COFF Char (no RELOCS_STRIPPED), Subsystem 0x000A, DllChar NX_COMPAT bit set.
- `tests/ovmf_smoke.sh` — runtime gate. Builds GPT-disk-with-ESP,
  copies `BOOTX64.EFI` + optionally `/boot/agnos`, boots under
  qemu-system-x86_64 + OVMF + `-cpu max`, greps ConOut serial. `EXPECT`
  and `AGNOS_KERNEL` are env hooks — the two v0.7.0 gates below drive it
  entirely through them, so no disk or QEMU logic is duplicated anywhere in
  the test tree.
- **⛔ Exit 77 means "did not run", and it is not a pass.** All three boot
  gates use it when tooling, firmware or a kernel is missing, and the two
  outer gates pass an inner 77 through. They exited 0 before v0.8.2.
- **Timing**, from a fast 16-core host under TCG: banner 2 s (default deadline
  20 s), `fail @ CODE` 2 s (12 s), `Launching kybernet` 8 s (25 s). QEMU never
  exits by itself, so every boot takes its full deadline.
- `tests/fetch_agnos.sh` — downloads the `agnos-x86_64` release asset and checks
  it against `SHA256SUMS`. The version is pinned in `tests/AGNOS_VERSION`.
- `tests/kaslr.sh` — **v0.8.3 gate, release-cut only.** Boots a PIE kernel and
  asserts each boot lands in the slide window, 2 MB-aligned, reaches `Launching
  kybernet`, and that the base varies, with a third boot to settle a 1-in-111 tie.
  Mutation-tested: fails on a stuck slide, no slide, a misaligned slide and an
  unslid entry. It trusts the kernel's echo of `kernel_base`, so it cannot see a
  gnoboot that misreports the address. Default deadline 60 s per boot.
- `tests/build_pie_agnos.sh` — builds the kernel for that gate from copies under
  `build/agnos-pie.*/`, about 85 MB each and left in place, with agnos's pinned
  toolchain. Never run agnos's PIE build in the agnos checkout: it overwrites the
  ET_EXEC `build/agnos` the other local gates boot.
- `AGNOS_KERNEL=<pie kernel> tests/multi_ptload.sh` runs the same split through the
  PIE branch; that is the coverage for its multi-segment span allocation.
- `tests/malformed_kernel.sh` — **v0.7.0 hardening regression gate**.
  Mutates a real agnos ELF64 one field at a time and boots **18**
  corrupted kernels under OVMF, asserting the specific 4-char failure
  code for each: 6 identity rejects (`ELF`), 5 program-header-table
  rejects (`PHN`), no-`PT_LOAD` (`PT`), and 6 segment-bounds rejects
  (`SZ`) including the truncated-kernel case. **This gate is the reason
  the hardening can be claimed at all** — `verify_pe.sh` and
  `ovmf_smoke.sh` both exercise only the happy path, so without it every
  bounds check is unexercised code, indistinguishable from an absent one.
- `tests/multi_ptload.sh` — **M5 positive gate**. Splits the real kernel's
  single `PT_LOAD` into two contiguous ones describing an identical memory
  layout (program-header table appended, `e_phoff` re-pointed; no kernel
  byte changes) and asserts baseline and split both reach
  `Launching kybernet`. Booting the baseline too means an environmental
  failure reports as such rather than being blamed on the split.
- Both run per push since v0.8.2, against the pinned kernel.

## CI / Release

- `.github/workflows/ci.yml` — every push + PR. Install cyrius
  (canonical install.sh + post-install smoke per the agnos pattern),
  build with `CYRIUS_TARGET_EFI=1`, run the structural gate, fetch the
  pinned agnos kernel, run all three boot gates against it, upload
  `BOOTX64.EFI` as artifact. **Proven at `55e8688`**: OVMF smoke 21 s,
  malformed-kernel 223 s, multi-`PT_LOAD` 120 s, all passing. **A step taking
  0 seconds means a gate did not boot.** `tests/kaslr.sh` is not wired in: the
  agnos release asset is ET_EXEC, so CI coverage of the PIE branch would need agnos
  to publish a PIE asset. It runs at release cuts instead.
- `.github/workflows/release.yml` — `v?X.Y.Z` tag trigger. CI gate,
  version-verify, build, publish `BOOTX64.EFI` + `gnoboot-X.Y.Z-x86_64-efi.efi`
  + `SHA256SUMS` to GitHub release via `softprops/action-gh-release@v2`.

## Dependencies

Direct (declared in `cyrius.cyml`):

None declared since v0.7.3. `src/main.cyr` includes one stdlib module directly:

- stdlib — `lib/fnptr.cyr` (`fncall0`–`fncall8`, the definitions that enable the
  compiler's inline MS x64 firmware-call lowering). Vendored from the `6.7.18`
  snapshot and tracked in git; never hand-edited. Since 6.6.5 no call site
  reaches its bodies (see § Binary), so a change there is no longer a boot-path
  change. The `6.7.9` → `6.7.18` delta is comment-only; the `6.6.20` → `6.7.9` one
  was real code (`cx` arms, and `fncall8`'s argument order on other targets) and
  emitted zero bytes here. No other stdlib deps; a UEFI Application is freestanding.

**⛔ `stdlib = ["fnptr"]` is commented out in `cyrius.cyml` — a workaround for a
cyrius bug, present at 6.6.20 and still at 6.7.18.** With it declared, build,
test, bench and fuzz all fail with `reserved intrinsic name 'fncall0'`. The
mechanism: `PP_EMIT_PKGVER` writes `var CYRIUS_PKG_VERSION = "…";` with no trailing
newline, so when the first prelude line is an `include`, that file's `#@file`
marker lands mid-line and `FM_BUILD` never registers it. The file reads as
`<source>`, and 6.6.20's exemption for files named `fnptr.cyr` does not apply.
Every consumer loses attribution on its first prelude include, but only gnoboot
has `fnptr` there, because `fnptr` is its only dep. Any line in between (even a
blank one) avoids it, and reordering is not available with one dep.

The workaround costs nothing at build time: `--no-deps` and the undeclared form
produce the same image. What it costs is the automatic re-vendor, so see
§ Toolchain before touching `lib/`. Tracked in the roadmap.

**The test target builds again** (it did not through v0.7.1). `cyrius test`,
`bench` and `fuzz` all pass at 6.7.18, on smoke-level cases only. They and
`src/test.cyr` reach stdlib modules that are not vendored, through the
compiler-side fallback to the pinned snapshot; that is deliberate, because
vendoring them would grow the one-file `lib/`. Neither release gate touches
this path — `verify_pe.sh` and `ovmf_smoke.sh` both work off
`build/BOOTX64.EFI`.

## Audit

- **First security audit — landed 2026-08-29**:
  [`docs/audit/2026-08-29-audit.md`](../audit/2026-08-29-audit.md), re-derived
  from `src/main.cyr` at tag `0.6.2`. **10 findings** (2 HIGH-severity pairs, 3
  MEDIUM, 4 LOW/INFO) and **9 verified-sound** paths. Satisfies the v1.0
  *"security audit pass"* criterion; **no code changed in that pass** — it is the
  scoping document for v0.7.0.
- **Disposition — v0.7.0 (2026-08-29) closed F1, F2, F3, F4, F6, F7, F9 and
  the F5 comment**, and reconciled `SECURITY.md`. Remaining open: **F8**
  (16 KB memmap buffer cannot grow — safe, brittle at >~340 descriptors;
  deferred because the sizing `AllocatePages` must precede the final
  `GetMemoryMap` or it invalidates the map key) and the **F5 decision**
  (flat struct vs. a real tag stream — M4's first task). F10 was
  informational, no action.
- **Re-run the audit after v0.7.0** before the v1.0 cut: the criterion is
  satisfied by having a pass, but the *sub-claims* changed materially, and
  the ET_DYN path has only had runtime coverage since v0.8.3.
- **Headline**: `SECURITY.md` § Threat model claims gnoboot defends against
  *"malformed kernel files … oversized program-header counts, malformed PT_LOAD
  entries. Bounds-checked at parse time"*. **None of those three clauses holds**
  — `e_phnum` is never read (only `phdr[0]` is honored), no `PT_LOAD` field is
  bounds-checked, and the pre-load ELF check is a single byte. The section's
  other two claims (fail-closed `GetMemoryMap`, straight-line map-key path) were
  verified sound. `SECURITY.md` must be reconciled in the same cut as the fixes.
- **The sharp pair** (both reachable *non-adversarially*, e.g. a truncated
  `\boot\agnos` from an interrupted write): the kernel segment `Read` never
  checks for a short read, and `p_filesz`/`p_memsz` are never bounded — so
  `p_filesz > p_memsz` overruns the allocation, and `p_memsz` near `u64::MAX`
  wraps `(p_memsz + 0xFFF) / 0x1000` to **zero pages**. `load_esp_blob` already
  guards *both* of these on the optional path — the mandatory kernel path is the
  less-safe one.
- **Roadmap reconciliation**: the audit produced the same work list the roadmap
  already had, better ordered. M5 (multi-`PT_LOAD`) is finding F2; M7
  (validation hooks) is F1 + F4; M4 (spec doc) is blocked on F5 (the `0x70`
  `kernel_base` store destroyed the tag-stream END terminator, and the in-file
  layout comment still documents an END there). Recommended next cut is
  **v0.7.0 "ELF-load hardening"** — M5 + M7 merged, since they are the same
  twenty lines.
- **Roadmap text is stale in one place**: M5 lists "zero-fills BSS" as future
  work; the code has done it since Step 7 (`main.cyr:503-511`, verified sound
  as S6).

## Consumers

> Per-field consumer status lives in
> [`docs/standards/handoff-protocol.md` § 8](../standards/handoff-protocol.md).
> **Three cross-repo items are open against agnos**, all filed by the M4 spec
> work and none of them gnoboot's to change:
> 1. **Erratum E2 — `mbi.cyr` reads `struct_size` with `load64(src + 8)`**, which
>    captures `flags` in the upper half. `ssz` is therefore always ≳2³² whenever a
>    flag bit is set, so its `min(struct_size, 128)` clamp is **always 128** — the
>    clamp exists precisely to stop a fixed 128-byte copy over-reading a 120-byte
>    struct, and reading the field as a `u64` makes that fix inert. Benign today;
>    it means agnos has no working bound from `struct_size`, which is the one
>    mechanism the spec's forward-compat rules rely on. Fix: `load32(src + 8)`.
> 2. **`flags` bit 2 (`kaslr_no_entropy`) has no reader.** Until it does, a KASLR
>    report cannot tell a real slide from the deterministic fallback.
> 3. **`fb_mode_chosen` needs a reader at `0x78`** for a burn to answer the
>    AMD-Zen scanout question. It carried no valid value before v0.7.1, so there
>    is nothing to migrate — only something to add.


- **agnos kernel** (≥ 1.47.4 for the KASLR/PIE path; ≥ 1.30.0 for the
  sovereign-struct contract itself) — receives `RDI = &boot_info` via
  gnoboot's Path C handoff. agnos boot-test CI fetches gnoboot's release
  asset directly. A non-PIE ET_EXEC kernel still loads at its `p_paddr`
  and is fully supported.

## Verified

- **v0.8.3 gates** (QEMU OVMF, 2026-11-01): image `ff75bf9f25b902e3…`, two builds
  reproduce it. Structural PASS. OVMF runtime PASS on real agnos 1.57.14.
  `malformed_kernel.sh` **18/18**. `multi_ptload.sh` **PASS**. `kaslr.sh` **PASS**.
  `multi_ptload.sh` on the PIE kernel **PASS**. `cyrius test`, `bench`, `fuzz` green.
- **ET_DYN / KASLR, measured at v0.8.3** on a PIE agnos 1.57.14 built with its
  pinned cyrius 6.6.20: `ET_DYN`, entry `0xa8`, one RWE `PT_LOAD` at 0.
  - **Where the image really is**, through the QEMU monitor rather than the kernel's
    echo: on 10 of 10 boots the ELF header is at the reported base and not at
    `0x100000`, and RIP is inside the slid image on every sample.
  - **Slide:** 22 boots at 256 and 512 MB, all in the window and 2 MB-aligned,
    12 of 12 to `Launching kybernet` in the first run.
  - **Re-roll:** at 128 MB all five bases landed in usable RAM (34–84 MB).
    Roughly a third of slots fit there, so five first-roll hits is about a 0.5%
    outcome. This is statistical, since gnoboot does not report re-rolls.
  - **Fallback:** 64 MB exhausts all 16 re-rolls and lands at `0x100000`. A mutant
    forced there at 256 MB reaches `Launching kybernet`.
  - **agnos panics at 64 and 128 MB, unrelated to gnoboot** (256 MB is fine). An
    ET_EXEC control panics at 64 MB too, so low-RAM boots cannot reach the marker. At
    128 MB the panic RIP was `base + 0x1A9719` on all five bases.
  - **Boot time follows host load, not the base.** The same base took 16.1 s and
    8.0 s, at a load average near 12.
  - **Not covered:** RDRAND exhausting its retries, which sets `flags` bit 2. QEMU's
    RDRAND does not fail. The PIE path has also never run on iron.
- **v0.8.2 gates** (QEMU OVMF, 2026-11-01; **CI proven at `55e8688`**): image `bf67a12de112a358…`.
  Local: structural PASS, OVMF runtime PASS on real agnos 1.57.14,
  `malformed_kernel.sh` **18/18**, `multi_ptload.sh` **PASS**, `cyrius test`, `bench`,
  `fuzz` green. **Runner simulation**, the same gates in CI's step order, under
  Ubuntu noble's `dash` and OVMF firmware with the fetched kernel: all PASS. Failure
  paths: with QEMU hidden the old gates exit 0 and the new ones 77; a stale banner
  fails `verify_pe.sh`; tampered and renamed agnos assets are refused.
- **v0.8.1 gates** (QEMU OVMF, 2026-11-01, **local only** — see § Open): build clean
  under cyrius 6.7.18 with the pin matching; two builds reproduce
  `8da01ba3a4452660…`. Structural PASS. OVMF runtime PASS —
  `gnoboot v0.8.1: handing off to kernel`, booting real agnos 1.57.14.
  `malformed_kernel.sh` **18/18**. `multi_ptload.sh` **PASS**. `cyrius test`, `bench`,
  `fuzz` green. `ud2 ud2` clean. Not re-disassembled, because the code is
  byte-identical to the v0.7.3 image below.
- **v0.8.0 gates** (QEMU OVMF, 2026-11-01, **local only** — see § Open): build clean
  under cyrius 6.7.9 with the pin matching; two builds reproduce
  `bf2ac65fa7ce51ed…`. Structural PASS. OVMF runtime PASS —
  `gnoboot v0.8.0: handing off to kernel`, booting real agnos 1.57.14.
  `malformed_kernel.sh` **18/18**. `multi_ptload.sh` **PASS**. `cyrius test`, `bench`,
  `fuzz` green. `ud2 ud2` clean. Not re-disassembled, because the code is
  byte-identical to the v0.7.3 image below.
- **v0.7.3 gates** (QEMU OVMF, 2026-11-01, **local only** — see § Open): build clean
  under cyrius 6.6.20 with the pin matching; two builds reproduce
  `ec7393fc9ca1b02b…`. Structural PASS. OVMF runtime PASS —
  `gnoboot v0.7.3: handing off to kernel`, booting real agnos 1.57.14.
  `malformed_kernel.sh` **18/18**, which is also the proof that `msg_fail` stayed
  patchable once baked. `multi_ptload.sh` **PASS**. `cyrius test`, `bench`, `fuzz`
  green. `ud2 ud2` clean. Disassembled: the landing (§ Binary), `rdrand_u64`, and
  the handoff tail; nothing between `mov rdi,rax` and `jmp rax` writes RDI. `boot_info`
  header read from the image: `0x41474E4F`, version 2, `struct_size` `0x80`.
- ⚠ **No release since the 6.6.5 entry change is iron-validated** (v0.7.3 through
  v0.8.1), and that matters more than usual: it changed the sequence every firmware
  call runs under, and
  cyrius's own notes say OVMF tolerates a misaligned CALL. **Run it on the next
  agnos burn.**
- **v0.7.1 gates** (QEMU OVMF, 2026-08-29): build clean under cyrius 6.5.36 with
  the pin matching (no drift warning). Structural PASS. OVMF runtime PASS —
  `gnoboot v0.7.1: handing off to kernel`, booting the real agnos ELF64.
  `malformed_kernel.sh` **18/18**. `multi_ptload.sh` **PASS**. `ud2 ud2` clean.
  **The 128-byte struct is consumer-compatible by demonstration, not argument**:
  agnos 1.56.52 validates `magic`, requires `struct_size >= 0x78`, and copies
  `min(struct_size, 128)` — the boot reaching the kernel proves the grown struct
  passes that validator unchanged. Field disjointness re-checked arithmetically:
  `fb_size` `0x68`–`0x6F`, `kernel_base` `0x70`–`0x77`, `fb_mode_chosen`
  `0x78`–`0x7B`, all inside `struct_size` `0x80`; no pair overlaps.
- **v0.7.0 gates** (QEMU OVMF, 2026-08-29): build clean under cyrius 6.5.36
  (pin `6.5.35`; benign drift). Structural gate PASS. OVMF runtime gate PASS
  — `gnoboot v0.7.0: handing off to kernel`, booting the real ~1.9 MB agnos
  ELF64 through to the **AGNOS shell**. `ud2 ud2` scan clean (0 occurrences).
  `tests/malformed_kernel.sh` **18/18**. `tests/multi_ptload.sh` **PASS**
  (baseline + 2-segment split both reach `Launching kybernet`). Both
  hand-verified codegen idioms re-disassembled after the `rdrand_u64` rewrite
  and the load-path restructure — see § Source.
- **v0.7.0 coverage gap — closed at v0.8.3.** The PIE branch shipped reasoned and
  disassembled but unrun, because agnos links ET_EXEC by default. See the v0.8.3
  entry above for what has now run and what still has not.
- **v0.6.2 gates** (QEMU OVMF, 2026-08-26): builds clean under cyrius
  6.5.35 with the re-vendored `lib/`. Structural gate PASS (subsystem
  0x000A, NX_COMPAT, no RELOCS_STRIPPED). OVMF runtime gate PASS —
  `gnoboot v0.6.2: handing off to kernel` on ConOut, booting the real
  1.9 MB `agnos` ELF64 payload. `ud2 ud2` scan clean (0 occurrences).
  Handoff sequence re-disassembled: nothing between `mov rdi, rax` and
  `jmp rax` writes RDI. **Iron re-validation rides the next agnos burn.**
- **QEMU OVMF emulation** (2026-05-13): gnoboot loads agnos kernel
  (251 KB ELF64) into `0x100000`, ExitBootServices succeeds, jumps with
  `RDI = &boot_info`. Kernel prints banner + 9 init checkpoints
  post-EBS through `Page tables: 1024MB mapped`.
- **Iron-validated on NUC AMD** — gnoboot's Path-C handoff is proven on
  archaemenid (Zen) across the agnos 1.40.x exec-from-disk arc (the
  `14013_final*` burn, 2026-05-31): UEFI → gnoboot → agnos boots clean through
  `Activating scheduler` → `Launching kybernet`.
- **v0.5.0 boot_info fills** (QEMU OVMF, 2026-06-03): the three pre-EBS
  fills run and the boot reaches handoff unchanged — OVMF's RSDP captured
  into `acpi_rsdp_phys` (0x38); absent `\boot\initramfs` + `\boot\cmdline`
  leave their fields `0` (benign). EFI `ud2` scan clean; GUIDs/offsets/ABI
  independently re-derived + confirmed by adversarial review. **Iron
  re-validation of the filled fields rides the next agnos burn** (and is
  only meaningful once the kernel reads them — see Open).

## Open

- **gnoboot executes `rdrand` without checking CPUID.** Found at the v0.8.3 cut with
  `-cpu max,rdrand=off`: a PIE load faults with `#UD` at gnoboot's own `rdrand`
  (image offset `0x1594`). The v0.7.0 retry covers RDRAND failing, not being absent,
  so this is a crash rather than the loud `flags` bit 2 fallback. ET_EXEC kernels
  never reach it and agnos needs RDRAND itself, so nothing shipping hits it. The
  fix touches `rdrand_u64`, one of the hand-verified idioms. Slotted for 0.9.0.
- **Audit F8 — the memory map cannot grow.** `mm_buf` is a fixed 16 KB and the
  size passed to `GetMemoryMap` matches it exactly, so it fails *closed* rather
  than truncating (audit S2, sound). But a machine whose map exceeds ~340
  descriptors simply will not boot, reporting only `MM`. The fix is UEFI's
  two-call sizing pattern, with the ordering constraint that the sizing
  `AllocatePages` must run **before** the final `GetMemoryMap` or it invalidates
  the map key. Deferred from v0.7.0; not a correctness bug.

- **boot_info feature-fill — LANDED at v0.5.0 (gnoboot side).** gnoboot now
  fills `initramfs_phys`/`size` (0x10/0x18) from `\boot\initramfs`,
  `cmdline_phys` (0x20) from `\boot\cmdline`, and `acpi_rsdp_phys` (0x38)
  from the EFI Configuration Table — all optional + benign-on-failure. The
  **cross-repo follow-on is agnos-side**: the kernel reads `acpi_rsdp_phys`,
  but `initramfs` and `cmdline` are diagnostic-only there (`core/initrd.cyr`
  mounts a synthetic INDR image from a fixed `0x6000`; no cmdline parser).
  Wiring the kernel to act on them, and settling the **initramfs
  format end-to-end** (gnoboot is deliberately format-neutral — sovereign
  INDR, not Linux cpio.gz), is the next step. Tracks the agnosticos
  read-only live-`.iso` path ([`iso-stage4-plan.md` § N1b]) — **the
  writable `.img` ISO cut needs none of it.** See [`roadmap.md` § Not gating v1.0].
- **Kernel now reads the inlined FB fields** (`fb_phys`/`pitch`/`width`/`height`)
  — supersedes the old "kernel stashes the pointer but doesn't dereference
  fields" note; the agnos 1.40.9 `boot_info_copy` fix reads them (it was the
  root cause of the ring-3 #PF — `fb_fb_phys` read `boot_info` ≥4 GB under the
  per-process CR3). The remaining unconsumed fields are
  initramfs/cmdline: gnoboot **has** filled these since v0.5.0 — they are
  waiting on kernel-side readers, not on gnoboot. (This bullet previously said
  gnoboot still passed 0 there; that stopped being true at v0.5.0.)
- **Scheduler-under-UEFI stall — CLOSED.** Was "kernel reaches
  `Activating scheduler` then resets." Root cause was an agnos-side bug (a dead
  exec proc resurrected by the scheduler), fixed at **agnos 1.40.10** (register
  kmain proc 0 + idle proc 1 on the boot CR3 before activation); iron-validated
  on the `14013_final*` burn — boots through to `Launching kybernet`. Not a
  gnoboot issue.
