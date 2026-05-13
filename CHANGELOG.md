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
