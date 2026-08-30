# AGNOS Sovereign Handoff Protocol — v1 (wire version 2)

> **Status**: authoritative. This document is the contract between gnoboot and
> any kernel it boots. Where this document and an implementation disagree, the
> **implementation is the bug** — except in § Errata, which records places the
> implementation is currently known to diverge and what will be done about it.
>
> **Roadmap**: milestone **M4**. Drafted 2026-08-29 at gnoboot **0.7.1**, whose
> struct growth (§ Errata **E1**) was found by writing it.
> **Not yet frozen** — freezing is a v1.0 criterion, and § Errata lists what
> must close first: **E1 fixed at 0.7.1**; **E2 is agnos-side and open**; **E3 is
> a decision owed at the freeze**.

## 0. Why this exists

gnoboot hands the kernel a struct and jumps. After `ExitBootServices` there is
no console, no firmware service, and no way to report a disagreement — a
mismatched expectation is a silent triple-fault on hardware with nothing on the
wire. Every field below is therefore specified with its **type, its offset, its
absent-value, and who owns its lifetime**, because "obvious" is not a property
that survives a cross-repo version skew.

The protocol is deliberately small. It carries what the kernel cannot discover
for itself once firmware is gone, and nothing else.

## 1. The handoff

gnoboot transfers control with:

```
    mov rdi, <&boot_info>
    jmp <entry>
```

| property | guarantee |
|---|---|
| **`RDI`** | Physical address of the `boot_info` struct. **The only register with a defined value.** |
| **All other GPRs** | **Undefined.** Do not read them. |
| **Stack** | Undefined. `jmp`, not `call` — **there is no return address**, and the kernel must not `ret`. gnoboot is gone. |
| **`entry`** | `e_entry` from the kernel ELF for `ET_EXEC`; `load_base + (e_entry - min_paddr)` for `ET_DYN`. See § 5. |
| **Boot services** | **Already exited.** `ExitBootServices` succeeded before this jump. Calling a boot service is undefined behaviour. |
| **Runtime services** | Still valid, reachable through `efi_st_phys` (§ 4). |
| **Paging** | The firmware's page tables, inherited unchanged. gnoboot does not touch `CR0`/`CR3`/`CR4`, and installs no GDT or IDT. Whatever UEFI left is what the kernel gets. |
| **Interrupts** | Whatever UEFI left. gnoboot executes no `cli`/`sti`. |
| **Kernel image** | Fully loaded: every `PT_LOAD` copied, every `[p_filesz, p_memsz)` gap zeroed. |

The kernel owns everything from instruction one. gnoboot never regains control.

## 2. Struct identity

| offset | type | field | value |
|---|---|---|---|
| `0x00` | `u32` | `magic` | `0x41474E4F` — `'AGNO'` little-endian |
| `0x04` | `u32` | `version` | `2` |
| `0x08` | `u32` | `struct_size` | `128` (`0x80`) — was `120` (`0x78`) through 0.7.0 |
| `0x0C` | `u32` | `flags` | bitfield, § 3 |

> ⚠ **`struct_size` is a `u32` at `0x08`, and `flags` is a separate `u32` at
> `0x0C`.** Reading `struct_size` as a `u64` captures both and yields
> `struct_size | (flags << 32)` — a number in the billions whenever any flag bit
> is set. **A consumer doing this silently loses every bound it thought
> `struct_size` gave it.** This is not hypothetical; see § Errata **E2**.

## 3. `flags` (`0x0C`, u32)

| bit | mask | name | meaning |
|---|---|---|---|
| 0 | `0x01` | `serial` | *Reserved.* Never set by any gnoboot release to date. |
| 1 | `0x02` | `fb_present` | The `fb_*` fields (§ 4) are populated. When clear, `fb_phys` is `0` and no framebuffer was found. |
| 2 | `0x04` | `kaslr_no_entropy` | **v0.7.0.** `RDRAND` could not supply entropy, so `kernel_base` (`0x70`) is the **deterministic fallback**, not a slide. A kernel reporting KASLR status **must** check this — a fallback base is a legal-looking slide value and is otherwise indistinguishable from a real one. |
| 3–31 | | | **Reserved. Must be zero.** A consumer must ignore unknown bits, never reject on them. |

Flags are set with read-modify-write OR. The bits are independent and may be set
by different stages of the boot.

## 4. Field reference

Offsets are from `RDI`. **Every field is at a fixed offset** (§ 6). `absent`
gives the value a consumer sees when gnoboot could not populate the field —
always `0`, always benign, never an error.

### Kernel inputs

| offset | type | field | absent | since | meaning |
|---|---|---|---|---|---|
| `0x10` | `u64` | `initramfs_phys` | `0` | 0.5.0 | Physical base of `\boot\initramfs`, loaded verbatim into `EfiLoaderData`. **Format-neutral by design** — gnoboot reports bytes and length; the kernel owns the format (sovereign INDR, *not* Linux `cpio.gz`). |
| `0x18` | `u64` | `initramfs_size` | `0` | 0.5.0 | Byte count. Paired with `0x10`; both are `0` or both are non-zero. |
| `0x20` | `u64` | `cmdline_phys` | `0` | 0.5.0 | Physical base of `\boot\cmdline`, a NUL-terminated UTF-8 blob in `EfiLoaderData`. **Termination is the image builder's responsibility** — gnoboot loads bytes and does not append a NUL. No length field: the NUL is the length. |

### Firmware-derived

| offset | type | field | absent | since | meaning |
|---|---|---|---|---|---|
| `0x28` | `u64` | `memmap_phys` | never `0` | 0.1.0 | Physical base of the UEFI memory map captured immediately before `ExitBootServices`. **Points into gnoboot's own loaded image** — see § 7. |
| `0x30` | `u32` | `memmap_count` | never `0` | 0.1.0 | Descriptor count = `MemoryMapSize / DescriptorSize`. |
| `0x34` | `u32` | `memmap_entsize` | never `0` | 0.1.0 | `DescriptorSize` in bytes. **Use this to stride, never `sizeof(EFI_MEMORY_DESCRIPTOR)`** — UEFI explicitly permits the firmware's descriptor to be larger than the spec's structure, and stepping by the wrong stride silently walks garbage. |
| `0x38` | `u64` | `acpi_rsdp_phys` | `0` | 0.5.0 | RSDP from the EFI Configuration Table, ACPI 2.0 GUID preferred with a 1.0 fallback. **Under UEFI the legacy EBDA / `0xE0000` scan finds nothing** — this is the only RSDP a UEFI boot has. Validate signature and checksum before trusting it. |
| `0x40` | `u64` | `efi_st_phys` | never `0` | 0.1.0 | The `EFI_SYSTEM_TABLE`. Boot services within it are **dead**; runtime services are live. |

### Framebuffer — valid only when `flags` bit 1 is set

| offset | type | field | absent | since | meaning |
|---|---|---|---|---|---|
| `0x48` | `u64` | `fb_phys` | `0` | 0.1.0 | Linear framebuffer physical base. `0` means no GOP (text-mode or headless firmware) — a correct kernel skips painting and boots on. |
| `0x50` | `u32` | `fb_pitch` | `0` | 0.1.0 | Bytes per scanline, computed as `PixelsPerScanLine * 4`. **32 bpp is assumed**, which is why formats 2 and 3 are refused (§ 5). |
| `0x54` | `u32` | `fb_width` | `0` | 0.1.0 | `HorizontalResolution` in pixels. |
| `0x58` | `u32` | `fb_height` | `0` | 0.1.0 | `VerticalResolution` in pixels. |
| `0x5C` | `u32` | `fb_pixel_format` | `0` | 0.1.0 | `0` = RGB, `1` = BGR. **`2` (BitMask) and `3` (BltOnly) are never handed over** — gnoboot refuses to select them, because the kernel writes the framebuffer directly and BltOnly has no linear framebuffer at all. |
| `0x60` | `u32` | `fb_mode_current` | `0` | 0.4.x | The GOP mode number the **firmware** booted with. |
| `0x64` | `u32` | `fb_mode_max` | `0` | 0.4.x | `MaxMode` — how many modes the firmware offered. |
| `0x68` | `u64` | `fb_size` | `0` | 0.4.x | `FrameBufferSize` (UEFI 2.10 §11.9.1) — the firmware's **authoritative** framebuffer extent. Prefer it over `pitch * height` for a write-combining remap range; fall back to `pitch * height` when `0`. **Occupies `0x68`–`0x6F` in full.** |
| `0x78` | `u32` | `fb_mode_chosen` | `0` | 0.6.1, **relocated 0.7.1** | The mode gnoboot **selected**. Equal to `fb_mode_current` when no larger RGB/BGR mode was offered; different when native-resolution selection fired and the firmware accepted it. Reading them together distinguishes *"nothing better existed"* from *"`SetMode` refused"*. **Was at `0x6C` through 0.7.0, where it never survived** — see § Errata E1. |

> ⛔ **`0x6C` is not a field.** It is the upper half of `fb_size`. Do not read it.

### Loader state

| offset | type | field | absent | since | meaning |
|---|---|---|---|---|---|
| `0x70` | `u64` | `kernel_base` | never `0` | 0.6.0 | The load base gnoboot actually used: the KASLR slide for `ET_DYN`, or the lowest page-aligned `p_paddr` for `ET_EXEC`. **Always read together with `flags` bit 2** — the value alone cannot tell a real slide from the fallback. |

**`0x7C`–`0x7F` is reserved padding, and `0x80` is the end of the struct.**
`struct_size` = 128 = `0x80`. Reserved bytes are zero and are the next append
site.

## 5. What gnoboot promises about the kernel image

Guarantees a consumer may rely on, all enforced before `ExitBootServices` and
all failing to a 4-character code on ConOut rather than proceeding:

- The image is **ELF64, little-endian, `EM_X86_64`**, and `e_type` is `ET_EXEC`
  or `ET_DYN`. Validated before any header field is used to drive an allocation.
- **Every `PT_LOAD` segment is loaded**, not just the first. The program-header
  table is bounded (`e_phentsize` = 56, `1 <= e_phnum <= 16`) and read in one
  pass before anything is allocated.
- Each segment's `[p_filesz, p_memsz)` gap is **zero-filled**. UEFI 2.x §7.2
  declares `AllocatePages` memory undefined; the kernel's `.bss` is
  nevertheless zero on entry.
- Every offset and length is **bounds-checked against the file's actual size**,
  and every firmware `Read` is checked for a short transfer.
- The whole image occupies **one contiguous allocation**, so inter-segment
  offsets survive a KASLR slide unchanged.
- Pages are allocated as **`EfiLoaderCode`**, not `EfiLoaderData` — firmware
  that NX-marks loader *data* under strict W^X would otherwise triple-fault the
  first instruction.
- **`ET_DYN`**: base is 2 MB-aligned in `[32 MB, 254 MB)`, chosen by `RDRAND`,
  with up to 16 retries and a deterministic `0x100000` fallback. The window's
  ceiling is the kernel's own 256 MB per-process-CR3 identity extent.

## 6. Compatibility rules

**`boot_info` is a flat, fixed-offset structure. There is no tag stream, and
there will not be one.** This settles audit finding **F5**: earlier layout
comments described an END-terminated tag list at `0x70`, which the v0.6.0
`kernel_base` store overwrote and which nothing ever walked. The decision is
deliberate, not merely a ratification of the accident:

- The reason fields are inlined at all is that the kernel's boot canary reads
  `fb_phys` from raw assembly at entry instruction one, before a stack exists.
  Walking a tag stream there is brutal.
- A tag walker over a firmware-influenced buffer is an unbounded loop over
  attacker-adjacent data — precisely the class of hazard the 2026-08-29 audit
  was written to remove.
- Fixed offsets are checkable by inspection. A tag stream is not.

Evolution is therefore **append-only**:

1. **New fields are appended** at the current end of struct, and `struct_size`
   grows. Existing fields never move and never change type.
2. **`version` does not change** for an append. It changes only when an existing
   field changes meaning, offset, or type — which is a **major** gnoboot version
   bump.
3. **`magic` never changes.** A different magic is a different protocol.
4. **Absent is always `0`**, and always benign. A consumer must never treat a
   zero optional field as an error.
5. **Unknown trailing bytes are ignored** by an older consumer; **missing
   trailing fields read as absent** by a newer one. Both directions work without
   negotiation, which is the entire point of `struct_size`.

### Required consumer validation

A kernel **must**, before dereferencing anything:

1. Check `RDI != 0`.
2. Check `magic == 0x41474E4F`. **Read it as a `u32`.**
3. Read `struct_size` **as a `u32` at `0x08`** and require `>= 0x78`.
4. Copy `min(struct_size, sizeof(your_buffer))` bytes into kernel-owned memory
   **below 4 GB**, and read every field from the copy thereafter.
5. On any failure, leave the pointer **zero** so downstream guards engage,
   rather than parsing a partially-trusted struct.

Step 4 is not optional bookkeeping. `RDI` points into gnoboot's image, which is
identity-mapped only under the boot `CR3`; a read after the first per-process
`CR3` is loaded page-faults in boot context where nothing catches it. This was a
real iron failure (agnos 1.40.9).

## 7. Memory lifetime

`ExitBootServices` does **not** free the loader's memory. Ownership after
handoff:

| region | type in the memory map | rule |
|---|---|---|
| `boot_info` itself, and `memmap_phys` | `EfiLoaderCode`/`EfiLoaderData` (gnoboot's PE image) | **Copy both before reclaiming loader memory.** They live inside gnoboot's image, which the kernel is otherwise free to reuse. |
| initramfs and cmdline blobs | `EfiLoaderData` | Valid until the kernel reclaims them. **Copy or pin before freeing `EfiLoaderData`.** |
| the kernel image | `EfiLoaderCode` | The kernel's own pages. Do not reclaim. |
| `efi_st_phys` and runtime-services code/data | `EfiRuntimeServicesCode`/`Data` | **Never reclaim** if runtime services will be called. |
| framebuffer at `fb_phys` | typically outside the map, or `EfiMemoryMappedIO` | Not RAM. Never add to a page allocator. |

## 8. Consumer status

As of agnos **1.56.52**:

| field | consumed? |
|---|---|
| `magic`, `struct_size` | ✅ validated at entry (`kernel/arch/x86_64/mbi.cyr`) — but see **E2** |
| `memmap_phys` / `count` / `entsize` | ✅ functional — `pmm_probe_memmap`, `pmm_extend_to_memmap`, `pmm_migrate_bitmap` |
| `fb_phys` / `pitch` / `width` / `height` / `size` | ✅ functional — `fb_console`, WC remap |
| `acpi_rsdp_phys` | ✅ functional — `acpi.cyr` falls back to it when the legacy scan fails, and validates signature + checksum first |
| `kernel_base` | ✅ functional — reported as the KASLR slide probe; also read by `sched.cyr` |
| `flags` bit 2 (`kaslr_no_entropy`) | ❌ **not yet read.** New at gnoboot 0.7.0; until the kernel reads it, a KASLR report cannot distinguish a real slide from the fallback. |
| `initramfs_phys` / `size`, `cmdline_phys` | ⚠ **diagnostic only.** Printed as hex at boot; nothing acts on them. `core/initrd.cyr` still mounts a synthetic INDR image from a fixed `0x6000`, and there is no cmdline parser. This is the open cross-repo item — the ISO Stage-4 read-only live-`.iso` path needs it. |
| `efi_st_phys` | ⚠ stored; no runtime-services caller yet |
| `fb_mode_current` / `fb_mode_max` | ⚠ diagnostic |
| `fb_mode_chosen` | ❌ **not read.** Newly functional at 0.7.1 (it carried no valid value before). A burn wanting the scanout answer needs a kernel-side reader at `0x78`. |

## Errata

Known divergences between this specification and the shipped implementations.
**Each must be closed or consciously accepted before the v1.0 freeze.**

### E1 — `fb_mode_chosen` (`0x6C`) has never reached the kernel *(gnoboot)*

`fb_mode_chosen` is a `u32` at `0x6C`. `fb_size` is a `u64` at `0x68`, occupying
`0x68`–`0x6F`. **They overlap**, and `src/main.cyr` writes `0x6C` first
(mode-selection block) and `0x68` second (post-`SetMode` geometry re-read) — so
the `u64` store lands last and destroys the mode.

A consumer reading `0x6C` therefore gets the **high 32 bits of
`FrameBufferSize`**, which is `0` for any framebuffer smaller than 4 GB — that
is, always. The field has read `0` since it was introduced at v0.6.1.

**This matters operationally.** `fb_mode_chosen` exists for exactly one purpose:
to let an iron burn distinguish *"no larger mode was offered"* from *"gnoboot
selected a larger mode and the firmware refused it"* — the open AMD-Zen
scanout question. Because it always reads `0`, on any machine whose
`fb_mode_current` is non-zero the diagnostic reports a **false positive**,
pointing at the wrong conclusion.

**The fix cannot be a reordering.** Writing `0x6C` last would put `best_mode`
into the high half of `fb_size`, and agnos reads `fb_size` with a full
`load64(bi + 0x68)` — it would see a framebuffer several gigabytes in size and
hand that extent to its WC remap. The two fields must be **separated**, which
means the struct grows to 128 bytes with `fb_mode_chosen` relocated to `0x78`
and `struct_size` becoming `0x80`. That is an append-only change under § 6 and
lands within agnos's existing 128-byte copy buffer.

**Status: FIXED at 0.7.1.** `fb_mode_chosen` moved to `0x78` and `struct_size`
grew `0x78` → `0x80`. Append-only per § 6 — every pre-existing field keeps its
offset and type, `version` stays `2`, and the growth lands inside agnos's
existing 128-byte copy buffer (it also removes that copy's 8-byte over-read as a
side effect). **A consumer built against 0.6.1–0.7.0 must not read `0x6C`**; a
consumer wanting the field must read `0x78` and require `struct_size >= 0x80`.

**The field has never carried a valid value in any released build**, so nothing
downstream regresses — there was no working reading to preserve.

### E2 — agnos reads `struct_size` as a `u64` *(agnos, cross-repo)*

`kernel/arch/x86_64/mbi.cyr` does `var ssz = load64(src + 8)`. Per § 2 that
captures `struct_size | (flags << 32)`. Since `flags` is non-zero on every boot
where a framebuffer was found, `ssz` is always ≳ 2³², so:

- `if (ssz >= 0x78)` passes for the wrong reason;
- `n = min(ssz, 128)` is **always 128**.

The clamp was added specifically to stop a fixed 128-byte copy from over-reading
gnoboot's 120-byte struct — its own comment says so. **Reading the field as a
`u64` makes that fix inert**, and the 8-byte over-read it was written to remove
still happens on every boot.

Benign today: the over-read stays inside gnoboot's `.data` and nothing consumes
those 8 bytes. But it means agnos has **no working bound** from `struct_size`,
which is the one mechanism § 6 relies on for forward compatibility.

**Fix (agnos-side)**: `load32(src + 8)`. One token. Filed here rather than
changed, because gnoboot does not modify agnos.

Note the interaction with **E1**: if gnoboot grows to 128 bytes, current agnos
copies exactly 128 and is correct *by accident*. Fixing E2 makes it correct on
purpose, and is what lets the struct grow again after that.

### E3 — `flags` bit 0 (`serial`) is specified but never set *(gnoboot)*

No gnoboot release has ever set it. Either give it a meaning or formally retire
it at the freeze; do not leave a documented bit that no producer writes.

## Change control

Changes to this document require a corresponding gnoboot release and a
CHANGELOG entry. Breaking changes — anything violating § 6 — additionally
require a **major** version bump and a migration note, per `CLAUDE.md`.

The v1.0 freeze makes § 2 through § 7 immutable for the 1.x series. § Errata
must be empty, or every remaining entry consciously accepted in writing, before
that freeze.
