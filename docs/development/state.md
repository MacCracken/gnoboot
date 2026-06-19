# gnoboot — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).
>
> **Last refresh**: 2026-06-19 (**v0.5.1 cut** — toolchain pin-bump patch release: `cyrius.cyml` pin `6.0.47` → `6.2.24`, banner version string `v0.5.0` → `v0.5.1`. No source behavior change beyond the banner; handoff contract + ABI byte-for-byte identical to v0.5.0. Builds clean on 6.2.x; structural + OVMF gates green; awaiting user tag). Prior: 2026-06-03 (**v0.5.0 cut** — the boot_info feature-fill release: `initramfs_phys`/`size` + `cmdline_phys` + `acpi_rsdp_phys` now populated pre-EBS, all optional + benign-on-failure; `cyrius.cyml` pin `6.0.14` → `6.0.47`. Multi-lens adversarial review confirmed GUIDs/offsets/ABI and added three robustness caps). 2026-06-01 (Open-section reconcile to the agnos 1.40.x reality — initramfs `boot_info`-fill flagged **P1**). 2026-05-28 (v0.4.3 — pin bump to 6.0.14).

## Version

**0.5.1** — cut 2026-06-19 (awaiting user tag). Toolchain **pin-bump
patch** release: `cyrius.cyml` pin `6.0.47` → `6.2.24` and the banner
version string `v0.5.0` → `v0.5.1`. **No source behavior change** beyond
the banner — boot path, handoff contract (magic `'AGNO'`, struct version
`2`, struct_size `0x78`), and ABI are byte-for-byte identical to v0.5.0.
Builds clean on the 6.2.x toolchain; structural + OVMF gates green
(banner reads `gnoboot v0.5.1`). The 0.4.2 SetMode-bounce code is retained
as-is (AMD-Zen scanout residue is kernel-side; see CHANGELOG [Unreleased]
signpost).

Prior — **0.5.0** (cut 2026-06-03): the **boot_info feature-fill**
release: three reserved fields that passed `0` since v0.1.0 are now
populated pre-ExitBootServices, all OPTIONAL + benign-on-failure (a normal
boot with no extra ESP files is byte-for-byte unaffected). No ABI change.
- `initramfs_phys` (0x10) / `initramfs_size` (0x18) ← `\boot\initramfs`
  (format-NEUTRAL path; kernel owns the format, sovereign INDR not Linux
  cpio.gz). The ISO live-`.iso` RAM-root gate.
- `cmdline_phys` (0x20) ← `\boot\cmdline` (forward-compat; no consumer yet).
- `acpi_rsdp_phys` (0x38) ← EFI Configuration Table walk (ACPI 2.0 GUID
  preferred, 1.0 fallback). Unblocks ACPI under UEFI.

## Toolchain

- **Cyrius pin**: `6.2.24` (in `cyrius.cyml [package].cyrius`) — advanced from
  `6.0.47` at the v0.5.1 cut. Builds clean, structural gate PASS, no `ud2 ud2`.
  (Build host wrapper is cycc 6.2.25; pin held at 6.2.24 per the user's
  explicit choice — known-good, not chased. The build emits a benign
  pin-drift warning; the pin is the source of truth, not the wrapper.)
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

## Binary

- **`build/BOOTX64.EFI`**: ~39 KB (PE32+ EFI Application, x86_64,
  subsystem 0x000A, NX_COMPAT + DYNAMIC_BASE + HIGH_ENTROPY_VA,
  `.reloc` populated). Bulk is the cyrius `fncallN` MS-x64-ABI
  trampolines from `lib/fnptr.cyr`; gnoboot's own code is ~2 KB
  (grew ~6 KB at v0.5.0 for the three optional fills + helpers).
- **Entry**: cyrius e9 jmp prologue at `.text+0`, jumps to auto-trampoline
  that captures `RCX → R14`, `RDX → R15`, then `call efi_main` (MS x64 ABI)

## Source

- `src/main.cyr` — single file, ~560 lines. UTF-16LE message constants
  (one `msg_pre` banner + one shared `msg_fail` template + 13
  per-stage `code_*` codes), EFI GUIDs (LoadedImage + SimpleFileSystem
  + GraphicsOutput + v0.5.0: FileInfo + ACPI 2.0/1.0), helpers
  `efi_print` / `efi_clear` / `efi_fail` + v0.5.0 `load_esp_blob` /
  `guid_eq`, entry `fn efi_main(handle, st)`. The v0.5.0 fills live in
  the `10d-f` block of `efi_main` (between GOP capture and the
  GetMemoryMap pair). Entry trampoline auto-emitted by cyrius.

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

- stdlib — `lib/fnptr.cyr` (`fncall1`–`fncall5` for MS x64 firmware-call
  dispatch; v0.5.0 added `fncall4` use for `GetInfo`/`AllocatePages`).
  No other stdlib deps; UEFI Application is freestanding.

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
- **v0.5.0 boot_info fills** (QEMU OVMF, 2026-06-03): the three pre-EBS
  fills run and the boot reaches handoff unchanged — OVMF's RSDP captured
  into `acpi_rsdp_phys` (0x38); absent `\boot\initramfs` + `\boot\cmdline`
  leave their fields `0` (benign). EFI `ud2` scan clean; GUIDs/offsets/ABI
  independently re-derived + confirmed by adversarial review. **Iron
  re-validation of the filled fields rides the next agnos burn** (and is
  only meaningful once the kernel reads them — see Open).

## Open

- **boot_info feature-fill — LANDED at v0.5.0 (gnoboot side).** gnoboot now
  fills `initramfs_phys`/`size` (0x10/0x18) from `\boot\initramfs`,
  `cmdline_phys` (0x20) from `\boot\cmdline`, and `acpi_rsdp_phys` (0x38)
  from the EFI Configuration Table — all optional + benign-on-failure. The
  **cross-repo follow-on is agnos-side**: the kernel does not yet read any
  of these (`core/initrd.cyr` mounts a synthetic INDR image from a fixed
  `0x6000`; no cmdline parser; `acpi_init` only does the legacy BIOS scan).
  Wiring the kernel to read `boot_info`, and settling the **initramfs
  format end-to-end** (gnoboot is deliberately format-neutral — sovereign
  INDR, not Linux cpio.gz), is the next step. Tracks the agnosticos
  read-only live-`.iso` path ([`iso-stage4-plan.md` § N1b]) — **the
  writable `.img` ISO cut needs none of it.** See [`roadmap.md` § v0.5.0].
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
