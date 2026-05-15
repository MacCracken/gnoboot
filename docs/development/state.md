# gnoboot — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).
>
> **Last refresh**: 2026-05-15 (v0.2 cycle — canary/output cleanup)

## Version

**0.1.0** — released 2026-05-13. First gnoboot release. AGNOS MVP
handoff verified end-to-end on QEMU OVMF.

**v0.2 cycle in progress** on branch `0.2`. No new ABI; canary code
removed, pre-EBS output consolidated. See CHANGELOG.md [Unreleased]
for the running summary; M1 in `roadmap.md` is the gate for cutting
v0.2.0.

## Toolchain

- **Cyrius pin**: `5.11.53` (in `cyrius.cyml [package].cyrius`)
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
- **Iron Attempt 5 on NUC AMD** — pending (next gnoboot validation pass;
  see agnosticos iron-boot log).

## Open

- **No agnos-kernel-side reading of `boot_info_ptr` yet** — kernel
  stashes the pointer but doesn't dereference fields. Memmap walking,
  cmdline, RSDP propagation are post-MVP. Tracked in agnos roadmap 1.30.x.
- **Iron Attempt 5** — USB re-provision + NUC AMD reboot pending user.
- **Scheduler-under-UEFI stall** (downstream of gnoboot; agnos issue)
  — kernel reaches `Activating scheduler`, then `pt_init`/`apic_init`
  fixed-physical assumptions break the post-scheduler path. Tracked
  in [agnos state.md § Open investigation](https://github.com/MacCracken/agnos/blob/main/docs/development/state.md).
