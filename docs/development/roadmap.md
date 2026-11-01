# gnoboot — Roadmap

> Release sequencing through v1.0 and notable post-v1 directions. State lives in
> [`state.md`](state.md), history in [`CHANGELOG.md`](../../CHANGELOG.md). Shipped
> work does not stay here.

**Released: 0.8.1.** Next: **0.8.2**.

| Release | Theme | Closes |
|---|---|---|
| **0.8.2** | Real boot gates in CI | CI boot gap, banner drift |
| 0.8.3 | ET_DYN / KASLR runtime coverage | the last untested load path |
| 0.9.0 | Pre-EBS hardening | audit F8, the remaining M7 hooks |
| 0.9.1 | Handoff contract closure | errata E2 and E3 |
| 1.0.0 | Handoff contract freeze | the v1.0 criteria below |

## 0.8.2 — Real boot gates in CI

All three CI boot gates SKIP and report success; the smoke step took 0 seconds at
`3ef5ad3`. That is how the stale `v0.7.1` banner got a green `0.7.2` release.
`release.yml` gates on `ci.yml`, so fixing CI covers tagged releases too.

- [ ] `tests/ovmf_smoke.sh` probes the `_4M` firmware names Ubuntu actually ships
      (`OVMF_CODE_4M.fd`, `OVMF_VARS_4M.fd`). `malformed_kernel.sh` and
      `multi_ptload.sh` go through this script, so they inherit the fix.
- [ ] CI fetches the `agnos-x86_64` release asset, checks it against that release's
      `SHA256SUMS`, and passes it as `AGNOS_KERNEL`. The agnos version is pinned in
      one place, so a kernel release cannot move gnoboot's CI unannounced.
- [ ] A gate that cannot run fails under CI instead of exiting 0. SKIP stays
      available for local runs.
- [ ] `tests/verify_pe.sh` asserts the banner in the image matches `VERSION`.
      Byte lists have been plain data since cyrius 6.6.16, so this now needs no
      QEMU and catches the 0.7.2 failure in seconds.

**Done when** a CI run shows the three boot gates passing in real time, and a
deliberately stale banner turns CI red.

## 0.8.3 — ET_DYN / KASLR runtime coverage

The PIE branch (span allocation, the F6 retry, the F7 mask) has been reasoned about
and disassembled but never run, because agnos links ET_EXEC by default. This is no
longer blocked: agnos builds a PIE kernel with `CYRIUS_PIE=1 ./scripts/build.sh`
and has its own `scripts/smoke/kaslr-smoke.sh`.

- [ ] Boot gnoboot against a PIE agnos build and confirm the kernel starts at the
      `kernel_base` gnoboot reported.
- [ ] Add a gnoboot gate: two boots land at different `kernel_base` values and both
      reach `Launching kybernet`.
- [ ] Settle where the gate runs. The agnos release asset is ET_EXEC, so without a
      PIE asset this stays a local and release-cut gate.

## 0.9.0 — Pre-EBS hardening

- [ ] **Audit F8: let the memory map grow.** `mm_buf` is a fixed 16 KB, so a machine
      past ~340 descriptors fails closed at `MM` and will not boot. Use UEFI's
      two-call sizing. The sizing `AllocatePages` must run **before** the final
      `GetMemoryMap`, or it invalidates the map key.
- [ ] **Memmap sanity (M7):** at least one usable region and total RAM of at least
      64 MB, with a distinct failure code.
- [ ] **`boot_info` self-consistency (M7):** assert `struct_size` matches the
      layout before EBS. Unblocked now that the struct is flat: there is no END
      terminator to walk.
- [ ] Regression cases for each new failure code, where QEMU can force the
      condition.

These hooks are always on. M7 specced an opt-out through `/boot/gnoboot.cfg`, but
gnoboot has no config parser, and these checks do not justify adding one.

## 0.9.1 — Handoff contract closure

The spec requires each erratum closed or consciously accepted before the freeze.

- [ ] **E3 (gnoboot):** `flags` bit 0 `serial` is specified but no release has ever
      set it. Give it a meaning or retire it.
- [ ] **E2 (agnos):** `kernel/arch/x86_64/mbi.cyr` still reads `struct_size` with
      `load64` at agnos 1.57.14, so its bound is inert. Needs `load32` on the agnos
      side, or an explicit acceptance recorded in the spec.
- [ ] Refresh the spec's § 8 consumer status, which still describes agnos 1.56.52.

## 1.0.0 — Handoff contract freeze

From v1.0 onward, no breaking change to the `boot_info` layout, magic or register
convention without a major bump. Downstream (agnos, ark, future bootable AGNOS
spinoffs) can then depend on a stable boot ABI.

- [ ] **Handoff struct frozen:** layout stable, no field renames, magic `0x41474E4F`
      locked, spec § Errata empty or consciously accepted.
- [ ] **Public surface frozen:** gnoboot is a binary, so this means the handoff
      contract and the ESP paths it reads, all documented.
- [ ] **Test coverage adequate:** 0.8.2 and 0.8.3 shipped, and structural and OVMF
      gates green in CI.
- [ ] **Iron-verified on 2+ platforms:** NUC AMD plus at least one other Zen or
      Intel UEFI box. QEMU-OVMF passes are *necessary but not sufficient*. Do not
      save this for the end: no release since 0.7.3 has been burned, and that is
      where the entry sequence changed, so the next agnos burn should check it.
- [ ] **Security audit re-run:** the 2026-08-29 pass predates all of the hardening
      it scoped.
- [ ] **CHANGELOG complete:** all 17 tags have a section as of 0.8.1. Still to check
      that early entries have the Breaking/Added/Changed/Fixed split where applicable.
- [ ] **v1 retrospective drafted** in `docs/development/retro/v1_cycle.md` before
      the tag, per the agnosticos retro pattern.

## Not gating v1.0

- **Restoring `stdlib = ["fnptr"]`.** Commented out in `cyrius.cyml` since v0.7.3 and
  waiting on a cyrius fix; still failing at 6.7.18. Details in `state.md`
  § Dependencies. Once a fixed cyrius is pinned, uncomment it, run `cyrius lib sync`,
  and confirm `lib/` stays one file and the image hash does not move.
- **agnos-side readers.** gnoboot fills these; acting on them is kernel work. The
  `initramfs_phys`/`size` and `cmdline_phys` fields are diagnostic-only there, and
  the kernel side tracks the agnosticos read-only live `.iso` path
  ([`iso-stage4-plan.md` § N1b](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iso-stage4-plan.md)).
  The initramfs format is the open contract: gnoboot stays format-neutral, and the
  kernel's sovereign INDR format is the AGNOS-native direction. `flags` bit 2
  (`kaslr_no_entropy`) has no reader, and `fb_mode_chosen` at `0x78` needs one
  before a burn can answer the AMD-Zen scanout question.
- **Verbose diagnostic mode (M6).** No v1.0 criterion needs it, and it must be
  re-scoped before building: it is specced as serial output, archaemenid has no
  serial cable, and the `/boot/gnoboot.cfg` that toggles it does not exist.
- **aarch64 UEFI port (M8).** Blocked: cyrius has no aarch64 EFI emit. No v1.0
  criterion needs it either, and because `boot_info` growth is append-only, anything
  the port adds can land after the freeze. It also needs AAPCS64 firmware calls and a
  decision on Pi 4 device-tree handling.

## Post-v1.0 directions

Notes for future agents — not promises, not committed slots. These
are the natural next surfaces if/when v1.0 lands. Each is a feature-
class lift.

### Secure Boot signing chain

UEFI Secure Boot integration. gnoboot signed by a custom CA; kernel
binary signed by the same CA; gnoboot verifies the kernel signature
before AllocatePages. Closes the firmware-to-kernel trust chain
under "no firmware compromise, no kernel tampering" assumptions.
Real engineering — cyrius needs to emit signed PE-COFF Authenticode
sections, AGNOS needs to integrate with Microsoft 3rd-party UEFI CA
(or self-managed KEK/PK on supported hardware).

### Multi-kernel selection menu

`/boot/gnoboot.cfg` declares 2+ kernels (current, previous, recovery,
testing). Boot menu via ConOut with keyboard input (timer-driven
default). Useful for in-place kernel upgrades that can roll back if
the new build doesn't boot.

### A/B partition selection

Robust upgrade pattern: two `\boot\agnos.a` / `\boot\agnos.b` slots,
gnoboot tries the "active" one, on boot failure (kernel resets within
N seconds or doesn't ack a heartbeat) switches the active marker.
Builds on multi-kernel selection.

### Disk encryption integration (LUKS / sovereign equivalent)

Unlock encrypted root partitions pre-kernel. Requires:

- A pre-EBS UI for passphrase entry (or TPM/FIDO unsealing)
- The unlock key passed to the kernel via `boot_info` (or post-EBS via
  some shared-memory region — TBD whether we trust DRAM through the
  kernel's first paging setup)
- AGNOS-native disk crypto crate (could fold into `sigil`)

### TPM integration / measured boot

PCR extensions for gnoboot's own measurement + kernel measurement +
boot-info measurement. Builds the foundation for TPM-sealed disk
keys and remote attestation.

### Network boot (PXE / HTTP boot)

UEFI's HTTP Boot service is decent on modern firmware. Fetch
`/boot/agnos` over HTTPS (UEFI does TLS), validate signature, boot.
Removes the USB-disk dependency for fleet provisioning.

### Recovery mode

Holding a key during boot (or a sentinel file in ESP) drops to a
minimal gnoboot shell — list ESP contents, dump boot-info struct,
manual kernel parameter override. Useful in field debugging without
needing a serial cable to capture the verbose-mode trace.

### Sovereign struct v2

A future major-version handoff-struct bump as AGNOS learns what it
*actually* needs from firmware. Likely additions: per-CPU TSS pre-
init, IOAPIC routing hints, ACPI table pre-walk results. Reserved
tag types in v1 leave space for additive fields without breaking the
v1 contract.

### Non-agnos kernel support

Could gnoboot boot Linux (sovereign-struct-shimmed) or BSD (similar)?
The handoff contract is the question. If the sovereign struct grows
the right reserved-tag adapters (multiboot2-compat tag, Linux Boot
Protocol-compat tag), gnoboot becomes a general-purpose UEFI loader
with AGNOS as the canonical consumer.

## Out of scope (for v1.0)

- **Windows / macOS guest support** — gnoboot is for AGNOS first. Adapter
  shims for other OS handoff protocols are post-v1 territory.
- **32-bit x86 (`IA-32`)** — UEFI Application emit could theoretically
  target 32-bit, but no AGNOS variant runs there. cyrius's UEFI emit is
  64-bit only; gnoboot follows.
- **CSM / BIOS boot fallback** — gnoboot is UEFI-native. Legacy BIOS
  is supported via the older `agnosticos/scripts/install-usb.sh` multiboot1
  path, which is on its own lifecycle.
- **Self-modification at runtime** — gnoboot's binary is read-only after
  firmware loads it. Configuration via `/boot/gnoboot.cfg` (text file on
  ESP), not via patching gnoboot itself.
