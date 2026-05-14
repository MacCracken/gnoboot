# gnoboot — Roadmap

> Milestone plan through v1.0 and notable post-v1 directions. State
> lives in [`state.md`](state.md); this file is the sequencing — what
> ships, in what order, against what dependency gates.

## v1.0 criteria

v1.0 freezes the gnoboot handoff contract + the firmware-to-kernel
guarantees. Once tagged, downstream (agnos, ark, future bootable AGNOS
spinoffs) can depend on a stable boot ABI.

- [ ] **Handoff struct v1 finalized** — `agnos_boot_info` layout
      stable, no field renames, magic `0x41474E4F` locked. Spec
      lives in `docs/standards/handoff-protocol.md` (earned at v0.5
      or so when more fields are populated).
- [ ] **All inlined fields populated** — initramfs, cmdline,
      memmap, ACPI RSDP, EFI SystemTable. v0.1.0 only fills
      memmap + efi_st_phys.
- [ ] **Iron-verified on 2+ hardware platforms** — NUC AMD (closed
      beta target) + at least one other Zen/Intel UEFI box.
      QEMU-OVMF passes are *necessary but not sufficient*.
- [ ] **Public API frozen** — every exposed symbol documented, no
      breaking changes accepted post-v1.0.
- [ ] **Test coverage adequate** — structural + OVMF gates green
      across the cyrius pin range used in CI.
- [ ] **CHANGELOG complete from v0.1.0 onward** — every release
      entry has a Breaking/Added/Changed/Fixed split where applicable.
- [ ] **Security audit pass** (`docs/audit/YYYY-MM-DD-audit.md`)
      — bounds on every Read, validated sizes from firmware-supplied
      structures, no path traversal in `\boot\agnos` resolution.
- [ ] **v1 retrospective drafted** in `docs/development/retro/v1_cycle.md`
      — what worked across v0.1 → v1.0, what didn't, what carries forward.

## Milestones — v0.x → v1.0

### M0 — v0.1.0 — ✅ shipped 2026-05-13

MVP handoff verified on QEMU OVMF. gnoboot loads
`\boot\agnos` from ESP, builds an 80-byte sovereign boot-info struct
(magic / version / struct_size / memmap_phys-count-entsize /
efi_st_phys + END tag), calls ExitBootServices, jumps to kernel
entry at `0x1000A8` with `RDI = &boot_info`. Pairs with **agnos
1.30.0** (sovereign-struct entry contract: `mbi_capture_rbx →
boot_info_capture_rdi`).

### M1 — v0.2.0 — iron-verified MVP

**Gate**: iron Attempt 5 on the NUC AMD passes. gnoboot v0.1.0 +
agnos 1.30.x USB re-provision; kernel boots through to its
`Activating scheduler` checkpoint on real hardware.

Closes the only outstanding v0.1.0 validation. No new gnoboot
features; this is a confidence cut. Whatever the iron run surfaces
(if anything) drives v0.2.x patches.

### M2 — v0.3.0 — cmdline + initramfs

Two adjacent fills of `boot_info` fields that are currently 0:

- **`cmdline_phys`** — read kernel command line from ESP file
  `\boot\cmdline` (NUL-terminated UTF-8); AllocatePages a page,
  copy contents, set `boot_info->cmdline_phys`.
- **`initramfs_phys` / `initramfs_size`** — read initramfs from
  `\boot\initramfs.cpio.gz` (or wherever AGNOS conventions land)
  into AllocatePages region, set the pair.

agnos kernel reads these (post-1.30.x agnos work). MVP for full
userland boot.

### M3 — v0.4.0 — ACPI RSDP + EFI Configuration Table walk

Set `boot_info->acpi_rsdp_phys` from UEFI's `SystemTable->ConfigurationTable`
search (find the `EFI_ACPI_TABLE_GUID` entry, copy the pointer).
agnos already has `acpi_init()`; today it falls back to legacy
BIOS probe (won't find anything under UEFI). Fixing this unblocks
ACPI hardware enumeration on iron without depending on the legacy
search path.

### M4 — v0.5.0 — handoff-protocol v1 spec doc

`docs/standards/handoff-protocol.md` written as the authoritative
spec. Every field documented; every reserved tag-type slot listed;
versioning rules + forward-compat rules pinned. **Hardens the contract
for v1.0.** Should be drafted before v0.5 ships (so v0.5 → v0.6 is the
test of "does the spec match the code").

### M5 — v0.6.0 — multi-PT_LOAD support

Today the kernel loader assumes a single PT_LOAD (true for agnos
1.30.x). v0.6.0 walks all `e_phnum` program headers, AllocatePages
per PT_LOAD, copies file segments into place, zero-fills BSS.
Forward-compat with kernels that may grow .data/.bss into separate
segments, and with non-agnos kernels (Linux's `bzImage` shape is
multi-segment under multiboot2; sovereign-struct can deliver that
too if a Linux variant ever wants to consume our handoff).

### M6 — v0.7.0 — verbose-serial diagnostic mode

`/boot/gnoboot.cfg` (UTF-8 INI-like) toggles a verbose mode that
serial-prints every firmware call result, every parsed ELF/program-
header field, every AllocatePages outcome, the boot-info struct
contents (hex-dump) before EBS. Off by default (silent boot when
disabled); on by default in `*.dev` builds. Costs ~1 KB binary
size, ~2 sec boot-time when enabled.

### M7 — v0.8.0 — boot-info validation hooks

Three optional security/sanity hooks before EBS:

- **Memmap sanity**: assert at least 1 usable region exists, total
  RAM ≥ minimum (defaults: 64 MB).
- **Kernel ELF magic + machine match**: re-verify after AllocatePages
  + Read (currently verified post-Read but worth a defensive
  re-check before jumping).
- **Handoff struct self-consistency**: walk the END terminator;
  assert `struct_size` matches the inlined-fields layout's computed
  size.

Each hook can be opt-out via `/boot/gnoboot.cfg`. Aimed at production
deployment where a stuck-at-EBS surface is better than booting a
kernel into a confused environment.

### M8 — v0.9.0 — aarch64 UEFI port

Pi 4 / aarch64 UEFI is the secondary AGNOS target. The cyrius PE
backend currently emits x86_64 only (subsystem 0x000A, machine
0x8664). The AArch64 UEFI Application port needs:

- cyrius support for `_TARGET_EFI_APPLICATION` on aarch64 (PE32+
  with `machine = 0xAA64`)
- gnoboot's MS x64 firmware-call trampolines replaced with AAPCS64
  variants
- Pi 4 device-tree handling (DTB pointer in boot-info? or kernel
  parses ACPI?)

Probably its own arc once the iron campaign concludes the x86_64
side.

### v1.0.0 — handoff contract freeze

When M1–M8 are green and the v1.0 criteria above are met. From v1.0
onward, no breaking changes to `boot_info` layout, magic, or register
convention without a major bump. Cuts the **v1 cycle retrospective**
in `docs/development/retro/v1_cycle.md` per the agnosticos retro
pattern.

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
