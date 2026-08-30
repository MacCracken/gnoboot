# gnoboot — Roadmap

> Milestone plan through v1.0 and notable post-v1 directions. State
> lives in [`state.md`](state.md); this file is the sequencing — what
> ships, in what order, against what dependency gates.

## v1.0 criteria

v1.0 freezes the gnoboot handoff contract + the firmware-to-kernel
guarantees. Once tagged, downstream (agnos, ark, future bootable AGNOS
spinoffs) can depend on a stable boot ABI.

- [ ] **Handoff struct v1 finalized** — `agnos_boot_info` layout
      stable, no field renames, magic `0x41474E4F` locked. **Spec
      SHIPPED at v0.7.1** —
      [`docs/standards/handoff-protocol.md`](../standards/handoff-protocol.md)
      (roadmap M4). **Not yet frozen**: freezing requires § Errata empty or
      consciously accepted. E1 fixed at v0.7.1; **E2 (agnos reads
      `struct_size` as a u64, so its bound is inert) and E3 (`flags` bit 0
      `serial` specified but never set) remain**.
- [ ] **All inlined fields populated** — initramfs, cmdline,
      memmap, ACPI RSDP, EFI SystemTable. v0.1.0 only fills
      memmap + efi_st_phys.
- [ ] **Iron-verified on 2+ hardware platforms** — NUC AMD (closed
      beta target) + at least one other Zen/Intel UEFI box.
      QEMU-OVMF passes are *necessary but not sufficient*.
- [ ] **Public API frozen** — every exposed symbol documented, no
      breaking changes accepted post-v1.0.
- [ ] **Test coverage adequate** — structural + OVMF gates green
      across the cyrius pin range used in CI. **Materially advanced at
      v0.7.0**: `tests/malformed_kernel.sh` (18 malformed kernels, each
      asserting its specific pre-EBS failure code) and
      `tests/multi_ptload.sh` (multi-segment equivalence) mean the
      hardening is exercised rather than merely written. Still open: the
      **ET_DYN / KASLR path is not runtime-tested** (agnos links ET_EXEC),
      and `src/test.cyr` still does not build.
- [ ] **CHANGELOG complete from v0.1.0 onward** — every release
      entry has a Breaking/Added/Changed/Fixed split where applicable.
- [x] **Security audit pass** — ✅ **first pass landed 2026-08-29**:
      [`docs/audit/2026-08-29-audit.md`](../audit/2026-08-29-audit.md).
      The criterion's three named sub-claims resolve as: *bounds on every
      Read* → **not met** (findings F3, F4 — fixed in v0.7.0); *validated
      sizes from firmware-supplied structures* → **partially met** (memmap
      fail-closed is sound; GOP/config-table counts are bounded
      inconsistently, F9); *no path traversal in `\boot\agnos` resolution*
      → **met by construction** (S3 — all three ESP paths are compile-time
      constants, nothing is concatenated). Re-run the pass after v0.7.0.
- [ ] **v1 retrospective drafted** in `docs/development/retro/v1_cycle.md`
      — what worked across v0.1 → v1.0, what didn't, what carries forward.

## boot_info feature-fill — ✅ LANDED at v0.5.0 (gnoboot side)

> Added 2026-06-01 as P1, **shipped 2026-06-03 at v0.5.0**. gnoboot now fills
> `initramfs_phys`/`size` (0x10/0x18) from `\boot\initramfs`, `cmdline_phys`
> (0x20) from `\boot\cmdline`, and `acpi_rsdp_phys` (0x38) from the EFI
> Configuration Table — all optional + benign-on-failure, no ABI change. Full
> detail in the v0.5.0 milestone below + CHANGELOG `[0.5.0]`.

**The remaining work is the cross-repo (agnos-side) consumer**, not gnoboot:
the agnosticos **ISO Stage-4 read-only live `.iso` path**
([`iso-stage4-plan.md` § N1b](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iso-stage4-plan.md))
needs the kernel to *read* `initramfs_phys`/`size` and run root from RAM — today
`core/initrd.cyr` mounts a synthetic INDR image from a fixed `0x6000` and ignores
the field. The **initramfs format is the open contract**: gnoboot is deliberately
format-neutral (`\boot\initramfs`, raw bytes), and the kernel's sovereign INDR
format — not Linux `cpio.gz` — is the AGNOS-native direction. **The writable
`.img` ISO form needs none of this** (iso-stage4-plan § N1a). `cmdline_phys` +
`acpi_rsdp_phys` also await kernel-side readers (cmdline parser; an ACPI
`boot_info` fallback ahead of the legacy BIOS probe).

## Milestones — v0.x → v1.0

> **⚠ Version labels below are stale.** The `v0.3.0`/`v0.4.0`/`v0.5.0` slots
> M2–M4 were assigned to already shipped the scanout-residue arc instead (see
> *Immediate priority* above). These feature-fills re-slot starting at the next
> feature release; the M-numbering is kept for continuity, not the versions.

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

### v0.5.0 — boot_info feature-fill (initramfs + cmdline + ACPI RSDP) — ✅ shipped 2026-06-03

> Consolidated the slipped M2/M3 fills into one release. All three use the same
> mechanism — read an ESP file or walk a firmware table, then populate a reserved
> `boot_info` field that previously passed **0**. The struct was already sized for
> them (v2, `0x78`); **no ABI bump, no struct-version change**. All three are
> OPTIONAL + benign-on-failure, so a normal boot is byte-for-byte unaffected.
> Also advanced the cyrius pin `6.0.14` → `6.0.47`.

Shipped:

1. **`initramfs_phys` / `initramfs_size` (0x10/0x18) — the ISO live-`.iso` gate.**
   Loads `\boot\initramfs` from the ESP into an `EfiLoaderData` region
   (`GetInfo` → `AllocateAnyPages` → `Read`) and sets the pair. **The path is
   format-NEUTRAL** (`\boot\initramfs`, no extension): gnoboot loads raw bytes and
   reports phys+size; the kernel owns the format. The earlier `\boot\initramfs.cpio.gz`
   plan was dropped — `cpio.gz` is a Linux-ism, and the kernel reads a sovereign
   INDR blob, not gzipped cpio (per the kernel-grows-per-native-workload principle).
   Keeping the format out of the gnoboot-visible name lets it evolve without
   re-cutting the loader.
2. **`cmdline_phys` (0x20).** Loads `\boot\cmdline` (NUL-terminated UTF-8) into an
   `EfiLoaderData` page. Optional; forward-compat (no kernel consumer yet).
3. **`acpi_rsdp_phys` (0x38).** Walks `SystemTable->ConfigurationTable`, prefers
   the ACPI 2.0 GUID and falls back to 1.0, and stores the matching `VendorTable`
   (the RSDP). Unblocks ACPI under UEFI, where the kernel's legacy BIOS probe
   finds nothing.

**Verified**: OVMF smoke (fills run, boot reaches handoff unchanged; OVMF RSDP
captured, absent files benign-`0`), EFI `ud2` scan clean, and a multi-lens
adversarial review (GUIDs/offsets/ABI re-derived + confirmed; three robustness
caps folded in). **Cross-repo follow-on (agnos-side)**: the kernel doesn't read
these yet (`core/initrd.cyr` mounts a synthetic INDR image from `0x6000`; no
cmdline parser; legacy-only ACPI). Wiring the kernel + settling the initramfs
format end-to-end is the next step; iron re-verify of the filled fields rides the
next agnos burn.

### M2 — cmdline + initramfs — ✅ ABSORBED into v0.5.0 above

> Historical M-number. The cmdline + initramfs fills are now the v0.5.0 scope
> (items 1–2). Kept for milestone-numbering continuity.

### M3 — ACPI RSDP + EFI Configuration Table walk — ✅ ABSORBED into v0.5.0 above

> Historical M-number. Now v0.5.0 item 3. Kept for continuity.

### M4 — handoff-protocol v1 spec doc — ✅ SHIPPED at v0.7.1

`docs/standards/handoff-protocol.md` written as the authoritative
spec. Every field documented; every reserved tag-type slot listed;
versioning rules + forward-compat rules pinned. **Hardens the contract
for v1.0.** Re-slots to **~v0.6.0** now that v0.5.0 is the boot_info
feature-fill; should be drafted once the v0.5.0 fills settle the field
layout (so the spec documents the as-shipped struct, not a moving target).

> ✅ **Shipped 2026-08-29 at v0.7.1**:
> [`docs/standards/handoff-protocol.md`](../standards/handoff-protocol.md).
> **F5 is settled — `boot_info` is flat and fixed-offset; there is no tag stream
> and there will not be one**, with append-only growth and `struct_size` as the
> sole authority. Not a ratification of the accident: the inlined layout exists
> because the kernel canary reads `fb_phys` from raw asm at entry instruction
> one; a tag walker over firmware-influenced data is an unbounded loop of exactly
> the class the audit was written to remove; and fixed offsets are checkable by
> inspection where a tag stream is not.
>
> **Writing it found a live bug** (spec erratum **E1**): `fb_mode_chosen` at
> `0x6C` overlapped `fb_size`'s u64 at `0x68` and was destroyed on every boot
> since v0.6.1 — the AMD-Zen scanout diagnostic had never once reached the
> kernel. Fixed in the same cut by relocating it to `0x78` and growing the struct
> to 128 bytes. **The overlap was invisible in a comment block ordered by when
> fields were added, and obvious in a table ordered by address.**
>
> **Still open before the v1.0 freeze**: erratum **E2** (agnos reads
> `struct_size` as a `u64`, so its bound is inert — agnos-side) and **E3**
> (`flags` bit 0 `serial` is specified but no producer sets it — give it a
> meaning or retire it).

<details><summary>Original M4 note (superseded)</summary>

> **The 2026-08-29 audit found the blocker (F5).** The spec cannot be written
> until one decision is made: **is `boot_info` a flat 120-byte struct, or a
> struct followed by a tag stream?** The layout comment says the latter and
> documents an END terminator at `0x70` — but v0.6.0's `kernel_base` store
> overwrote it, so no terminator exists and `struct_size` still reports 120. No
> shipped consumer walks tags (agnos reads fixed offsets), so nothing is broken
> today; but *"every reserved tag-type slot listed"* is a v1.0 criterion, and the
> struct currently contradicts its own documentation. Either declare it flat and
> drop the tag-stream concept, or grow it to 128 bytes and restore an END at
> `0x78`. **That call is M4's first task, not its last.**

</details>

### M5 — multi-PT_LOAD support — ✅ SHIPPED at v0.7.0 (merged with M7)

> **Re-scoped by the 2026-08-29 audit** ([`docs/audit/2026-08-29-audit.md`](../audit/2026-08-29-audit.md),
> finding **F2**). The version label `v0.6.0` is stale — that slot went to the
> KASLR / ET_DYN arc. M5 and M7 turned out to be **the same twenty lines of
> code**, so they ship together as v0.7.0 below.

Today the kernel loader assumes a single PT_LOAD: `e_phnum` is never read, only
`phdr[0]` is honored, and a first program header that is not `PT_LOAD` is a hard
`PT` failure. The audit reclassifies this from *forward-compat feature* to
**correctness bug** — a kernel with 2+ `PT_LOAD` segments (any hardened RX-text /
RW-data split) is **silently under-loaded**, not cleanly rejected. `e_phentsize`
is likewise assumed to be 56 with no check.

v0.7.0 walks all `e_phnum` program headers, AllocatePages per PT_LOAD, copies
file segments into place, zero-fills each BSS gap. Forward-compat with kernels
that may grow .data/.bss into separate segments, and with non-agnos kernels
(Linux's `bzImage` shape is multi-segment under multiboot2; sovereign-struct can
deliver that too if a Linux variant ever wants to consume our handoff).

> **Correction**: this section previously listed *"zero-fills BSS"* as future
> work. gnoboot has zeroed `[p_filesz, p_memsz)` since Step 7
> (`src/main.cyr:503-511`) precisely because `AllocatePages` does not guarantee
> zeroed memory (UEFI 2.x §7.2) — audit S6, verified sound. What v0.7.0 adds is
> doing it **per segment** rather than for the single assumed one.

### v0.7.0 — ELF-load hardening (M5 + M7 merged) — ✅ shipped 2026-08-29

> **Scoped by the 2026-08-29 audit, shipped the same day.** The audit did not
> produce a work list parallel to this roadmap — it produced the same list,
> better ordered. Every item below is an audit finding; severities are per
> `SECURITY.md`'s rubric. Full detail, including the verified-sound paths that
> needed no change, is in
> [`docs/audit/2026-08-29-audit.md`](../audit/2026-08-29-audit.md).
>
> **All nine items below landed.** The release is gated by two new tests —
> `tests/malformed_kernel.sh` (18 corrupted kernels booted under OVMF, each
> asserting its specific failure code) and `tests/multi_ptload.sh` (the real
> kernel's `PT_LOAD` split in two, proven to boot equivalently). **Not an ABI
> change**: only an additive `flags` bit 2.
>
> **Carried forward**: audit **F8** (the 16 KB memmap buffer cannot grow — safe
> but brittle; the sizing `AllocatePages` must precede the final
> `GetMemoryMap`), and the **F5 decision** (flat struct vs. real tag stream),
> which is M4's first task. Also owed: a **runtime run of the ET_DYN / KASLR
> path**, which agnos's current ET_EXEC link leaves unexercised.

The unifying observation: **`load_esp_blob` — the *optional* initramfs/cmdline
path added at v0.5.0 — is already hardened the way the *mandatory* kernel path
is not.** Most of this release is "bring the kernel load up to what the optional
load already does."

1. **F1 (HIGH) — validate the ELF header before using it.** The pre-load check is
   one byte (`0x7F`). Add the remaining magic bytes, `EI_CLASS`, `EI_DATA`,
   `e_machine == 0x3E`, and `e_phentsize == 56` — **before** `e_phoff` is allowed
   to drive `SetPosition`. This is M7's *"kernel ELF magic + machine match"* hook,
   moved to where it gates rather than where it merely backstops.
2. **F2 (MEDIUM) — walk all `e_phnum` program headers.** This is M5, above.
3. **F3 (HIGH) — check for short reads.** UEFI 2.10 §13.5.1 lets `Read` transfer
   fewer bytes and still return `EFI_SUCCESS`. `load_esp_blob` already guards
   this; the kernel segment read and both header reads do not.
4. **F4 (HIGH) — bound `p_filesz` / `p_memsz` / `p_offset`.** Reject
   `p_filesz > p_memsz` (copy overrun) and cap `p_memsz` before the page-count
   arithmetic (wrap → zero-page allocation). `load_esp_blob`'s 1 GiB cap is the
   precedent, and its comment already names the identical overflow.
5. **F6 (MEDIUM) — make KASLR fail loudly.** Retry `rdrand` on CF=0 (Intel
   guidance: 10 attempts) and set a `boot_info` flags bit on exhaustion, so the
   kernel reports *"KASLR: entropy unavailable"* instead of a fixed 32 MB base
   that is indistinguishable from a randomized one.
6. **F7 (LOW) — mask instead of negate** in the KASLR slide, so `i64::MIN` cannot
   escape the window.
7. **F9 (LOW) — bound the remaining firmware-supplied counts** for consistency
   with the ACPI walk's existing 256 cap: `max_mode` in the `QueryMode` loop,
   `ctab == 0`, and `dsz == 0`.
8. **F5 (MEDIUM) — correct the `boot_info` layout comment**, which still documents
   an END terminator at `0x70` that the v0.6.0 `kernel_base` store overwrote. The
   *decision* about what the struct actually is belongs to M4, below; v0.7.0 only
   stops the comment from lying.
9. **Reconcile `SECURITY.md`** in the same cut — its threat model currently claims
   bounds-checking that items 1–4 are what actually implement.

**Deferred as planned**: the **memmap sanity** hook and the two-call
`GetMemoryMap` sizing pattern (audit F8 — safe today, just brittle at >16 KB
maps; the sizing `AllocatePages` must happen *before* the final `GetMemoryMap`
or it invalidates the map key), and the **handoff struct self-consistency**
hook, which cannot be written until M4 settles F5.

### M6 — verbose-serial diagnostic mode — **re-slot and re-scope before building**

> **⚠ Flagged by the 2026-08-29 audit.** The version label `v0.7.0` is now taken
> by the hardening cut above. More importantly: this milestone is specced as
> *serial*-print diagnostics, and **archaemenid has no serial cable** — which is
> exactly why the 0.4.0 kernel-side audit results were made to sink to CMOS. A
> serial-only diagnostic mode does not help the one box that matters. Re-scope
> to the transport that reached iron (CMOS, or the framebuffer) before building
> it, or accept that it is a QEMU-only convenience.


`/boot/gnoboot.cfg` (UTF-8 INI-like) toggles a verbose mode that
serial-prints every firmware call result, every parsed ELF/program-
header field, every AllocatePages outcome, the boot-info struct
contents (hex-dump) before EBS. Off by default (silent boot when
disabled); on by default in `*.dev` builds. Costs ~1 KB binary
size, ~2 sec boot-time when enabled.

### M7 — boot-info validation hooks — ✅ two of three SHIPPED at v0.7.0

> **Re-scoped by the 2026-08-29 audit.** Two of the three hooks below are audit
> findings F1 and F4 and ship in v0.7.0. The third cannot be written yet — see
> the note under *Handoff struct self-consistency*. Kept for milestone-numbering
> continuity.


Three optional security/sanity hooks before EBS:

- **Memmap sanity**: assert at least 1 usable region exists, total
  RAM ≥ minimum (defaults: 64 MB).
- **Kernel ELF magic + machine match**: re-verify after AllocatePages
  + Read (currently verified post-Read but worth a defensive
  re-check before jumping).
- **Handoff struct self-consistency**: walk the END terminator;
  assert `struct_size` matches the inlined-fields layout's computed
  size. **⛔ Cannot be written as specced** — audit **F5** found there
  *is* no END terminator: the v0.6.0 `kernel_base` store at `0x70`
  overwrote it, so a tag walker reads `type = low32(kernel_base)` and
  `size = 0`. Blocked on M4 deciding whether boot_info is a flat
  120-byte struct or a struct plus a real tag stream.

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
