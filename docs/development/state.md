# gnoboot — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).
>
> **Last refresh**: 2026-06-01 (Open-section reconcile to the agnos 1.40.x reality — initramfs `boot_info`-fill flagged **P1** as the ISO live-`.iso` gate; the iron-validation, scheduler-stall, and boot_info-deref items closed/corrected). Prior: 2026-05-28 (v0.4.3 — cyrius toolchain pin bump to 6.0.14).

## Version

**0.4.3** — released 2026-05-28. Toolchain-pin release: advances the
`cyrius.cyml` pin from `6.0.1` to `6.0.14` (clears manifest-vs-wrapper
drift). No ABI change; boot_info struct version `2`, magic `'AGNO'`,
struct_size `0x78` unchanged since 0.4.0. The 0.4.2 SetMode-bounce code
is retained as-is — the gnoboot-side GOP `SetMode` lever for the AMD-Zen
Quiet-Boot scanout residue is exhausted (see CHANGELOG [Unreleased]
signpost; next channel is kernel-side).

## Toolchain

- **Cyrius pin**: `6.0.14` (in `cyrius.cyml [package].cyrius`)
- Required cyrius features:
    - 5.11.49 — `_TARGET_EFI_APPLICATION` PE32+ EFI emit mode
    - 5.11.51 — byte-array literal `var foo[N] = { 0x.., 0x.., ... };`
    - 5.11.52 — `fn efi_main(handle, st)` auto-trampoline + lib/fnptr.cyr
      TARGET_WIN branches under TARGET_EFI
    - 5.11.53 — entry-save REX prefix hotfix (gnoboot agent filed)

## Binary

- **`build/BOOTX64.EFI`**: ~33 KB (PE32+ EFI Application, x86_64,
  subsystem 0x000A, NX_COMPAT + DYNAMIC_BASE + HIGH_ENTROPY_VA,
  `.reloc` populated). Bulk is the cyrius `fncallN` MS-x64-ABI
  trampolines from `lib/fnptr.cyr`; gnoboot's own code is ~1.5 KB.
- **Entry**: cyrius e9 jmp prologue at `.text+0`, jumps to auto-trampoline
  that captures `RCX → R14`, `RDX → R15`, then `call efi_main` (MS x64 ABI)

## Source

- `src/main.cyr` — single file, ~375 lines. UTF-16LE message constants
  (one `msg_pre` banner + one shared `msg_fail` template + 13
  per-stage `code_*` codes), EFI GUIDs (LoadedImage + SimpleFileSystem
  + GraphicsOutput), helpers `efi_print` / `efi_clear` / `efi_fail`,
  entry `fn efi_main(handle, st)`. Entry trampoline auto-emitted by
  cyrius.

## Tests

- `tests/verify_pe.sh` — fast structural gate (5 PE header fields).
  Asserts DOS magic, PE sig, COFF Char (no RELOCS_STRIPPED), Subsystem
  0x000A, DllChar NX_COMPAT bit set.
- `tests/ovmf_smoke.sh` — runtime gate. Builds GPT-disk-with-ESP,
  copies `BOOTX64.EFI` + optionally `/boot/agnos`, boots under
  qemu-system-x86_64 + OVMF + `-cpu max`, greps ConOut serial. SKIPs
  gracefully when tooling absent.

## CI / Release

- `.github/workflows/ci.yml` — every push + PR. Install cyrius
  (canonical install.sh + post-install smoke per the agnos pattern),
  build with `CYRIUS_TARGET_EFI=1`, run structural + OVMF gates,
  upload `BOOTX64.EFI` as artifact.
- `.github/workflows/release.yml` — `v?X.Y.Z` tag trigger. CI gate,
  version-verify, build, publish `BOOTX64.EFI` + `gnoboot-X.Y.Z-x86_64-efi.efi`
  + `SHA256SUMS` to GitHub release via `softprops/action-gh-release@v2`.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — `lib/fnptr.cyr` (`fncall2`, `fncall3`, `fncall5` for MS x64
  firmware-call dispatch). No other stdlib deps; UEFI Application is
  freestanding.

## Consumers

- **agnos kernel** (≥ 1.30.0) — receives `RDI = &boot_info` via gnoboot's
  Path C handoff. agnos 1.30.x boot-test CI fetches gnoboot's release
  asset directly.

## Verified

- **QEMU OVMF emulation** (2026-05-13): gnoboot loads agnos kernel
  (251 KB ELF64) into `0x100000`, ExitBootServices succeeds, jumps with
  `RDI = &boot_info`. Kernel prints banner + 9 init checkpoints
  post-EBS through `Page tables: 1024MB mapped`.
- **Iron-validated on NUC AMD** — gnoboot's Path-C handoff is proven on
  archaemenid (Zen) across the agnos 1.40.x exec-from-disk arc (the
  `14013_final*` burn, 2026-05-31): UEFI → gnoboot → agnos boots clean through
  `Activating scheduler` → `Launching kybernet`.

## Open

- **`initramfs_phys` / `initramfs_size` fill — P1 (ISO live-`.iso` gate).**
  gnoboot reserves these fields (struct v2, offsets `0x10`/`0x18`) but passes
  **0** (MVP). The agnosticos read-only live `.iso` path needs gnoboot to load
  `\boot\initramfs.cpio.gz` into an `AllocatePages` region and fill the pair so
  the kernel (`core/initrd.cyr`) runs root from RAM. See
  [`roadmap.md` § Immediate priority](roadmap.md) + agnosticos
  `iso-stage4-plan.md` § N1b. **The writable `.img` ISO cut needs none of this.**
  `cmdline_phys` (M2 cmdline half) + `acpi_rsdp_phys` (M3) ride the same release.
- **Kernel now reads the inlined FB fields** (`fb_phys`/`pitch`/`width`/`height`)
  — supersedes the old "kernel stashes the pointer but doesn't dereference
  fields" note; the agnos 1.40.9 `boot_info_copy` fix reads them (it was the
  root cause of the ring-3 #PF — `fb_fb_phys` read `boot_info` ≥4 GB under the
  per-process CR3). The only *unconsumed* fields are the not-yet-filled ones
  above (initramfs/cmdline/RSDP) — because gnoboot passes 0, not because the
  kernel ignores them.
- **Scheduler-under-UEFI stall — CLOSED.** Was "kernel reaches
  `Activating scheduler` then resets." Root cause was an agnos-side bug (a dead
  exec proc resurrected by the scheduler), fixed at **agnos 1.40.10** (register
  kmain proc 0 + idle proc 1 on the boot CR3 before activation); iron-validated
  on the `14013_final*` burn — boots through to `Launching kybernet`. Not a
  gnoboot issue.
