# Changelog

All notable changes to gnoboot will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

> **Next-cycle signpost for the AMD-Zen Quiet-Boot scanout residue** (closed out at 0.4.2): the gnoboot-side GOP `SetMode` lever is exhausted on archaemenid. **Do NOT propose another SetMode variant** — both same-mode (0.4.1, Attempt 74) and different-mode bounce (0.4.2, Attempt 78) are firmware-elided on AMD Zen UEFI. Next channel for the bug is **kernel-side**, not gnoboot-side: either a minimal-redesign port of Linux's HUBP `clear_tiling` sequence (per amd-gfx ML; 3-6 MMIO writes per HUBP; DCN1→DCN3 register offsets inherited; Cezanne PCI BAR0 of `1002:1638`), OR an architectural decision about adopting shadow-buffer semantics for the AGNOS FB-console layer (simpledrm-style, per `archintel` Attempt 79 cross-check finding). Intel cross-check on archintel was structurally inconclusive (no BGRT table, hybrid Intel+NVIDIA GPU, Linux uses simpledrm). Older single-iGPU Intel box with BGRT-publishing firmware is the parked future discriminator. Full closeout record in `agnosticos/docs/development/iron-nuc-zen-log.md` § Attempt 79; memory pin: `project_amd_zen_scanout_residue`.

## [0.5.0] — 2026-06-03

The **boot_info feature-fill** release. Three reserved `boot_info` fields
that have passed `0` since v0.1.0 are now populated from the ESP / firmware
tables, pre-ExitBootServices. All three are **OPTIONAL + benign-on-failure**
(GOP-style): a missing file or absent table leaves the field `0` and the
boot proceeds unchanged — a normal AGNOS boot (writable `.img`, no extra ESP
files) is byte-for-byte unaffected. No struct/ABI change.

Advances the `cyrius.cyml` toolchain pin `6.0.14` → `6.0.47` (the first pin
that both fixes *and* guards the `CYRIUS_TARGET_EFI` `ud2`-at-`fncallN` emit
regression — cyrius v6.0.46). Builds clean; the EFI `ud2 ud2` byte-scan is
clean; structural + OVMF gates green.

### Added

- **`initramfs_phys` (0x10) / `initramfs_size` (0x18)** — loads
  `\boot\initramfs` from the ESP into a fresh `EfiLoaderData` region
  (`GetInfo` → `AllocatePages(AllocateAnyPages, EfiLoaderData)` → `Read`)
  and fills the pair. The upstream dependency for the agnosticos read-only
  live-`.iso` path (RAM root). **Path is format-NEUTRAL by design**:
  gnoboot loads raw bytes and reports phys+size; the kernel owns the
  initramfs format (sovereign INDR today — *not* a Linux `cpio.gz`). The
  earlier `\boot\initramfs.cpio.gz` plan was a Linux-ism that doesn't fit
  AGNOS's kernel-grows-per-native-workload posture; the format is
  deliberately kept out of the gnoboot-visible name so it can evolve
  without re-cutting the loader.
- **`cmdline_phys` (0x20)** — loads `\boot\cmdline` (NUL-terminated UTF-8)
  into an `EfiLoaderData` page and fills the field. Forward-compat: no
  kernel consumer yet.
- **`acpi_rsdp_phys` (0x38)** — walks `SystemTable->ConfigurationTable`
  (`st+0x68` count, `st+0x70` table, 24-byte entries), prefers the ACPI
  2.0 GUID and falls back to 1.0, and stores the matching `VendorTable`
  (the RSDP physical pointer). Unblocks ACPI under UEFI, where the kernel's
  legacy EBDA / `0xE0000` ROM scan finds nothing.
- Shared `load_esp_blob` (2-param, reads stashed root/Open/AllocatePages
  globals) + `guid_eq` helpers. Hardening from the v0.5.0 adversarial
  review: a 1 GiB `fsize` sanity cap (firmware `FileSize` is unchecked),
  a short-read guard (UEFI `Read` may transfer fewer bytes on success),
  and a 256-entry cap on the config-table walk.

### Changed

- **`cyrius.cyml` toolchain pin**: `6.0.14` → `6.0.47`.
- **Banner**: `gnoboot v0.4.3: …` → `gnoboot v0.5.0: …` (`msg_pre`
  UTF-16LE digits at char positions 11/13).
- **`tests/ovmf_smoke.sh` default `EXPECT`**: matches the new banner.

### Wire compatibility

**No struct version bump.** boot_info magic `'AGNO'`, struct version `2`,
struct_size `0x78`, and all field offsets are unchanged from 0.4.x — these
fields were reserved at those offsets since v0.1.0; v0.5.0 just stops
passing `0`. A kernel that doesn't read them is unaffected; a kernel that
does sees real values when the corresponding ESP file / ACPI table exists.

### Consumer status (cross-repo)

gnoboot deliberately **leads its consumer**. As of agnos 1.40.x the kernel
does **not** yet read these fields: `core/initrd.cyr` mounts a synthetic
INDR image from a fixed `0x6000`, there is no cmdline parser, and
`acpi_init()` only runs the legacy BIOS scan. Wiring the kernel to read
`boot_info` (and settling the initramfs format end-to-end) is a separate
agnos-side follow-on; this release makes the data available at the contract.

### Verified

- `tests/verify_pe.sh` PASS — PE32+ EFI Application, Subsystem `0x000A`,
  NX_COMPAT, no RELOCS_STRIPPED.
- `tests/ovmf_smoke.sh` PASS — `"gnoboot v0.5.0: handing off to kernel"`
  observed on ConOut under qemu + OVMF; the new pre-EBS fills run (OVMF
  RSDP captured into `0x38`; absent initramfs/cmdline → benign `0`) and
  the boot reaches handoff unchanged.
- EFI `ud2 ud2` byte-scan clean (cyrius v6.0.46 guard).
- Adversarial multi-lens review: GUID byte-order, struct offsets, and
  MS-x64 `fncallN` arities all independently re-derived and confirmed;
  the only findings were the robustness caps now folded in.

## [0.4.3] — 2026-05-28

Toolchain-pin release. Advances the `cyrius.cyml [package].cyrius` pin from
`6.0.1` to `6.0.14`, resolving the manifest-vs-wrapper drift the cycc emits as
a `toolchain drift` warning. No source-logic change beyond the banner version
bump; the binary rebuilds clean and both gates pass.

### Changed

- **`cyrius.cyml` toolchain pin**: `6.0.1` → `6.0.14`. cycc on the build host
  is already 6.0.14; the pin now matches, clearing the snapshot drift warning.
- **Banner**: `gnoboot v0.4.2: handing off to kernel` → `gnoboot v0.4.3: …`.
  UTF-16LE byte at character position 13 (the second digit in 'v0.4.2')
  updated `0x32` → `0x33` in `src/main.cyr` `msg_pre`.
- **`tests/ovmf_smoke.sh` default `EXPECT`**: `"gnoboot v0.4.2: …"` →
  `"gnoboot v0.4.3: …"` to match the new banner.

### Wire compatibility

**No struct version bump.** boot_info magic `'AGNO'`, struct version `2`,
struct_size `0x78`, field offsets — all unchanged from 0.4.0/0.4.1/0.4.2.
The SetMode-bounce code from 0.4.2 is retained as-is (no new lever; see the
[Unreleased] signpost). Wire format identical.

### Verified

- `tests/verify_pe.sh` PASS — DOS magic, PE sig, COFF Char (no RELOCS_STRIPPED),
  Subsystem `0x000A`, DllChar NX_COMPAT.
- `tests/ovmf_smoke.sh` PASS — `"gnoboot v0.4.3: handing off to kernel"`
  observed on ConOut under qemu + OVMF.

## [0.4.2] — 2026-05-20 — **FALSIFIED on iron Attempt 78 (2026-05-20)**

> **Iron result**: No flicker observed on VGA or HDMI; Quiet Boot banded-glyph signature identical to Attempt 77 (0.4.1). Per the pre-bound decision tree below ("If iron shows no flicker, that's a tell that the firmware is also eliding the different-mode bounce"), archaemenid's AMD Zen UEFI firmware elides the different-mode SetMode bounce in addition to the same-mode form falsified at Attempt 74. The OSDev #57150 recipe — that *the work of switching modes* flips the scanout buffer to linear regardless of mode diff — does not generalize to this firmware. Honest caveat: gnoboot 0.4.2 does not stamp `rc_a` from the bounce-mode SetMode (see `src/main.cyr:383`), so CMOS alone can't distinguish (a) bounce ran with both calls elided, vs (b) firmware rejected `bounce_mode = 1` and fell back to the same-mode call. Both routes have the same destination — GOP SetMode at gnoboot post-FB-read time isn't a viable lever on this firmware — so resolving (a) vs (b) doesn't change the next move. Per `feedback_no_instrumentation_means_no_instrumentation`, adding the stamp slot is off-table.
>
> **Disposition**: 0.4.2 stays released and shipped — the bounce code itself is well-formed, the falsification is of the *firmware-side workaround hypothesis*, not of the implementation. boot_info wire format unchanged across 0.4.0/0.4.1/0.4.2. Quiet Boot legibility moves out of the gnoboot-side lever space; if/when re-prioritized, the next channel for the H2 (FB-layer divergence) hypothesis is kernel-side direct DCN pipe reprogram (Linux `drivers/gpu/drm/amd/display/` analog — multi-kiloline, deferred). See `agnosticos/docs/development/iron-nuc-zen-log.md` § Attempt 78 for the full falsification record.

Transient SetMode-bounce release. Replaces 0.4.1's `SetMode(gop, cur_mode)` ("same-mode re-arm") with a two-call bounce: `SetMode(gop, bounce_mode)` → `SetMode(gop, cur_mode)`. Targets the surviving Quiet Boot ON garbled-glyph residue from Attempt 77 (iron 2026-05-20) on archaemenid, where 0.4.1's same-mode call was falsified — firmware elides same-mode SetMode as a no-op, no CRTC reprogram happens, and the scanout buffer stays in whatever non-linear / DCC-compressed state the BGRT logo path left it in. Per OSDev forum #57150 the linear flip is a side effect of the *mode-switch work*, not of any geometry diff; bouncing to a different mode and back forces the firmware to do real work that can't be elided, ending at the same final geometry the kernel was already prepared for.

### Changed

- **`SetMode` call in `efi_main` step 10c** expanded from a single `fncall2(fn_setmode, gop_p, cur_mode)` to a guarded two-call bounce:
  - `bounce_mode = 0` (or `1` when `cur_mode == 0`) — mode 0 is conventionally the lowest-res fallback every GOP implementation exposes, most likely to force a real CRTC reprogram.
  - `max_mode <= 1` (single-mode firmware) falls through to the 0.4.1 same-mode call — known-falsified but harmless, diagnostically equivalent.
  - First `SetMode(gop, bounce_mode)` failure (`EFI_UNSUPPORTED` / `EFI_DEVICE_ERROR`) falls back to a same-mode call so the firmware has a chance to reset to a known state.
  - Second `SetMode(gop, cur_mode)` failure leaves the display at `bounce_mode`; the post-SetMode geometry re-read at line 360+ captures whatever's actually live so `boot_info` reflects the true landed mode (no kernel-side panic, no inconsistent state, just degraded resolution).
- **`max_mode` read** moved from post-SetMode geometry re-read up to immediately after `cur_mode` (needed to gate the bounce branch). All other field reads (`mode_inf`, `fb_phys`, `fb_size`, `fb_w`, `fb_h`, `pf`, `ppl`) stay post-SetMode where 0.4.1 placed them.
- **Banner**: `gnoboot v0.4.1: handing off to kernel` → `gnoboot v0.4.2: handing off to kernel`. UTF-16LE byte at character position 13 (the second digit in 'v0.4.1') updated `0x31` → `0x32`.
- **`tests/ovmf_smoke.sh` default `EXPECT`**: `"gnoboot v0.4.1: …"` → `"gnoboot v0.4.2: …"` to match the new banner.

### Falsifies

- **0.4.1's same-mode SetMode hypothesis.** UEFI 2.10 §11.9.1.2 doesn't *require* firmware to elide same-mode SetMode, but archaemenid's AMD Zen iGPU firmware does in practice — confirmed by Attempt 74 iron (no visual change post-call) and aligned with OSDev #57150's observation that the linear flip is downstream of *the mode-switch work*, not of mode parameter changes. The 0.4.1 release notes claimed Linux `efifb.c` / EDK2 `GraphicsConsoleDxe` / FreeBSD `framebuffer.c` precedent for the same-mode form — those references actually motivate "SetMode is required before trusting FrameBufferBase" but don't pin down whether same-mode or different-mode SetMode is the operative pattern. 0.4.2 picks different-mode.

### Visible side effect

A real mode switch causes the display to flicker briefly during boot — through `bounce_mode` (typically 640×480 or similar low-res) and back to `cur_mode`. Acceptable; documents itself as the new expected boot signature. If iron shows no flicker, that's a tell that the firmware is also eliding the different-mode bounce.

### Wire compatibility

**No struct version bump.** boot_info magic `'AGNO'`, struct version `2`, struct_size `0x78`, field offsets — all unchanged from 0.4.0/0.4.1. The bounce is gnoboot-internal and invisible to the kernel-side ABI. Wire format identical.

### Decisive outcome shape (pre-bound iron decision tree)

- **Quiet Boot legible end-to-end at 2560×1440 after the bounce**: H2 confirmed, durable workaround. Close 1.30.12. Tag this release.
- **Quiet Boot still banded, identical signature to Attempt 77**: bounce is also being elided or the divergence is deeper than per-mode state (e.g., DCC compression is set per-buffer, not per-mode). Escalates to kernel-side DCN reprogram (deferred multi-kiloline work).
- **Quiet Boot banded, *different* signature**: bounce changed scanout state but didn't fully fix it; new artifact pattern may suggest tile-format vs DCC distinction.
- **Display ends at unexpected resolution**: second SetMode failed; iron post-mortem reads `boot_info.fb_mode_current` to learn the actual landed mode.
- **VGA-spec path regression**: bounce broke the previously-working VGA-spec path. Revert to 0.4.1; bounce isn't viable on this firmware; escalate directly to DCN reprogram.

### References

- OSDev forum thread #57150 — *"EFI GOP lying about screen resolution?"* — names the AMD tiled/DCC scanout mechanism and the mode-switch-work-flips-linear observation that motivates the bounce form.
- EDK2 `MdeModulePkg/Universal/Console/GraphicsConsoleDxe` — uses GOP `Blt()` rather than direct FB writes; `Blt()` unavailable post-EBS to gnoboot, hence the SetMode-driven workaround.
- Linux `drivers/gpu/drm/amd/display/` (DCN init) — kernel-side scanout reprogramming reference impl; the deferred fallback if the bounce is also falsified.
- `freebsd/drm-kmod` issue #60 — confirms upstream consensus that firmware-left state on AMD iGPUs at GOP handoff is untrustable for direct CPU writes.
- Iron Attempt 74 (`agnosticos/docs/development/iron-nuc-zen-log.md`) — falsified the 0.4.1 same-mode form.
- Iron Attempt 77 (same file) — research pass that identified the bounce variant as the next untried lever; H1 (renderer math) + H3 (font layout) falsified by code audit, H2 (FB-layer divergence) supported by prior art.

## [0.4.1] — 2026-05-19

Scanout re-arm release. Adds an explicit `gop->SetMode(gop, cur_mode)` call between GOP capture and ExitBootServices, forcing the firmware display controller to re-establish the CRTC scanout pipe pointing at `FrameBufferBase` before the kernel takes over paint. Targets the archaemenid Quiet Boot ON garbled-glyph residue that survived Attempt 73 (Burn A) — geometry was correct, BAR placement was identifiable, MTRR + PCI audits had ground to compute on, but the kernel was painting to a `FrameBufferBase` the display controller wasn't actually scanning from. The kernel-side audit results from 0.4.0 now sink to CMOS (no serial cable on iron), so a single iron burn answers both "does SetMode close the bug" and "what MTRR/PCI delta did we see."

### Added

- **GOP `SetMode(gop, cur_mode)` call** in `efi_main` step 10c, immediately after capturing `cur_mode` and before any boot_info field writes. Reads the SetMode fn pointer at `gop+0x08` (UEFI 2.10 §11.9.1, `EFI_GRAPHICS_OUTPUT_PROTOCOL.SetMode` member offset) and invokes it via `fncall2(fn_setmode, gop_p, cur_mode)`. Setting the current mode is the minimal-risk variant — no resolution change, just forces firmware to re-arm scanout. Return value intentionally ignored: capture fields stay valid as fallback if SetMode is rejected by firmware. Pattern sourced from Linux `drivers/video/fbdev/efifb.c::efifb_setup` (treats `FrameBufferBase` as authoritative only after explicit `SetMode`), EDK2 `MdeModulePkg/Universal/Console/GraphicsConsoleDxe` (uses the `Blt` service rather than direct framebuffer writes for the same scanout-divergence reason), and FreeBSD `stand/efi/loader/framebuffer.c` (documents AMD APU breakage absent `SetMode`).

### Changed

- **Capture order reshuffled.** `mode_inf` / `max_mode` / `fb_phys` / `fb_size` / `fb_w` / `fb_h` / `pf` / `ppl` reads now happen *after* the `SetMode` call. UEFI 2.10 §11.9.1.2 permits firmware to reallocate the FB BAR and relocate the `Mode->Info` structure pointer on a `SetMode` invocation; reading first and then calling `SetMode` would leave the captured values pointing at the pre-`SetMode` state. The reshuffle keeps `cur_mode` read pre-`SetMode` (the argument needed for the call) and everything else post-`SetMode`.

- **Banner**: `gnoboot v0.4.0: handing off to kernel` → `gnoboot v0.4.1: handing off to kernel`. UTF-16LE byte at character position 13 (the second '0' in 'v0.4.0') updated `0x30` → `0x31`.

- **`tests/ovmf_smoke.sh` default `EXPECT`**: `"gnoboot v0.4.0: …"` → `"gnoboot v0.4.1: …"` to match the new banner.

### Wire compatibility

**No struct version bump.** boot_info magic `'AGNO'`, struct version `2`, struct_size `0x78`, field offsets — all unchanged from 0.4.0. The SetMode call is gnoboot-internal and invisible to the kernel-side ABI. Wire format identical.

### References

- UEFI 2.10 §11.9.1 — `EFI_GRAPHICS_OUTPUT_PROTOCOL.SetMode` definition + scanout side effects
- Linux `drivers/video/fbdev/efifb.c::efifb_setup` — canonical pattern for "treat FrameBufferBase as scanout-authoritative only after SetMode"
- EDK2 `MdeModulePkg/Universal/Console/GraphicsConsoleDxe` — `Blt()`-based avoidance of direct FB writes
- FreeBSD `stand/efi/loader/framebuffer.c` — AMD APU breakage caveat
- Burn-A iron result write-up in `agnosticos/docs/development/iron-nuc-zen-log.md` § Attempt 73 — falsifications and the scanout-divergence diagnosis that motivated this release

## [0.4.0] — 2026-05-19

`FrameBufferSize` capture release. Adds the third GOP field gnoboot was dropping — `Mode->FrameBufferSize` (UEFI 2.10 §11.9.1, offset 0x20 of `EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE`) — so the agnos kernel can WC-remap the firmware-authoritative FB extent instead of computing `pitch * height` and hoping the BAR matches. Lands as part of the Attempt 73 audit-driven repair bundle targeting the archaemenid Quiet Boot ON garbled-glyph residue from Attempt 72 (geometry CMOS capture showed clean `pitch=width*4 BGRX`, falsifying pitch-padding + pf-≥-2 hypotheses; BAR-placement / BAR-extent divergence is the surviving candidate this release helps close).

### Added

- **GOP `Mode->FrameBufferSize` capture** at `boot_info+0x68` (u64, little-endian). Reads from `gop->Mode->FrameBufferSize` (offset 0x20 of the `EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE` struct) — the authoritative byte-extent of the framebuffer BAR per UEFI 2.10 §11.9.1 ("amount of memory required to hold the frame buffer"). Stamped in the existing GOP-locate block at `efi_main` step 10c, pre-EBS, alongside `fb_phys` / `fb_pitch` / etc. Companion to the kernel-side `fb_size_or_fallback()` accessor that prefers this value over the legacy computed `pitch * height` for WC-remap range selection.

- **Inline struct layout comment** in `src/main.cyr` extended to document the new field and call out the wire-version rationale.

### Changed

- **Boot-info struct size**: `112 (0x70)` → `120 (0x78)`. END tag relocates from offset `0x68` → `0x70`. Wire version stays **v2** because no consumer walks the tag stream — agnos kernel reads inlined fields at fixed offsets only, and the END move is invisible to fixed-offset readers. Pre-Attempt-73 agnos kernels reading `load64(boot_info+0x68)` under a v2-without-size gnoboot would have hit the END tag's zero; the kernel-side `fb_size_or_fallback()` falls back to `pitch * height` on zero — backward-compatible.

- **`boot_info[14]` → `boot_info[15]`**: array sizing follows the struct-size bump (14 × 8 = 112 → 15 × 8 = 120 bytes).

- **Banner**: `gnoboot v0.3.0: handing off to kernel` → `gnoboot v0.4.0: handing off to kernel`. UTF-16LE byte at position 22 updated (0x33 → 0x34).

- **`tests/ovmf_smoke.sh` default `EXPECT`**: `"gnoboot v0.3.0: …"` → `"gnoboot v0.4.0: …"` to match the new banner.

### References

- UEFI 2.10 §11.9.1 — `EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE.FrameBufferSize` definition
- Linux `drivers/firmware/efi/libstub/screen_info.c` — canonical `FrameBufferSize` capture in the EFI stub
- FreeBSD `stand/efi/loader/framebuffer.c::efi_find_framebuffer` — same field honored
- Attempt 73 prep block in `agnosticos/docs/development/iron-nuc-zen-log.md` — full repair audit

## [0.3.0] — 2026-05-19

FB-handoff diagnostic-extension release. Captures the two GOP fields gnoboot was previously dropping (`Mode->Mode` and `Mode->MaxMode`) so the agnos kernel can see which GOP mode the firmware selected — the load-bearing input for diagnosing the archaemenid quiet-boot vs VGA-spec divergence (Attempt 71: VGA-spec passes, Quiet Boot still returns the Attempt-33 garbled-glyph signature; `pf`-aware-PixelFormat hypothesis falsified). Also pins to cycc 6.0.1 directly (clears the v5.11.x→v6.0.0 toolchain-drift warning, picks up 6.0.1's UEFI-emit `fncallN` patch — see `agnosticos/docs/development/issues/2026-05-19-cycc-6.0.0-uefi-fncall-ud2-emit.md` for the bug write-up that motivated the 6.0.1 cut).

### Added

- **GOP `Mode->Mode` capture** at `boot_info+0x60` (u32, little-endian). Reads from `gop->Mode->Mode` (offset 0x04 of the `EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE` struct) — which mode the firmware actually booted with. Stamped in the existing GOP-locate block at `efi_main` step 10c, pre-EBS.

- **GOP `Mode->MaxMode` capture** at `boot_info+0x64` (u32, little-endian). Reads from `gop->Mode->MaxMode` (offset 0x00) — how many modes the firmware enumerates total. Helps distinguish "firmware exposes 1 mode only — no mode-set capability" from "firmware ran QueryMode iteration internally and picked a winner."

- **Inline struct layout comment** in `src/main.cyr` extended to document the two new fields and call out the reserved-slot overlay rationale.

- **`docs/architecture/001-sovereign-handoff-contract.md`** updated end-to-end. Was documenting the original v1/80 B layout (pre-v0.1.0 canary); now reflects the actual v2/112 B wire with `fb_phys` / `fb_pitch` / `fb_width` / `fb_height` / `fb_pf` inlined at `0x48-0x60` plus the new `fb_mode_current` / `fb_mode_max` overlay at `0x60-0x68`. Struct size note in body prose corrected from "80 B" to "112 B."

### Changed

- **Banner**: `gnoboot v0.2.0: handing off to kernel` → `gnoboot v0.3.0: handing off to kernel`. UTF-16LE bytes in `msg_pre` updated; one byte changes (0x32 → 0x33 at position 22).

- **`cyrius.cyml` pin**: `cyrius = "5.11.59"` → `"6.0.1"`. Picks up 6.0.1's UEFI-emit `fncallN` regression patch (cycc 6.0.0 had silently emitted `ud2 ud2` sentinels in place of `call` instructions at every `fncallN` site under `CYRIUS_TARGET_EFI=1`; the `CYRIUS_TARGET_EFI → CYRIUS_TARGET_WIN` predefine implication that `lib/fnptr.cyr`'s MS-x64 ABI branch depends on didn't survive the cc5 → cycc rename ceremony, so the body never emit'd). Drift warning cleared.

- **`tests/ovmf_smoke.sh` default `EXPECT`**: `"gnoboot v0.2.0: …"` → `"gnoboot v0.3.0: …"` to match the new banner.

### Wire compatibility

**No struct version bump.** `boot_info` magic `'AGNO'` unchanged; struct version field unchanged at `2`; struct_size unchanged at 112 B. The new fields at `0x60`/`0x64` overlay the previously-reserved u64 — v2 readers that don't know about the overlay see zeros there (the old reserved interpretation) and behave unchanged. Readers that DO know (agnos 1.30.12+) get the GOP mode #. RDI handoff contract, MS x64 → SysV ABI boundary at the kernel jump, ExitBootServices irrevocability — all preserved.

### Build

```
$ CYRIUS_TARGET_EFI=1 ~/.cyrius/bin/cyrius build src/main.cyr build/BOOTX64.EFI
compile src/main.cyr -> build/BOOTX64.EFI [x86_64]
note: 4 unreachable fns (0 bytes — set CYRIUS_DCE=1 to eliminate, CYRIUS_DCE_VERBOSE=1 to list)
OK
```

Binary size: **33,792 B** (was 32,768 B at 0.2.0; +1,024 B = the new capture + the extended layout comment block + cycc 6.0.1's slightly-different .text alignment). Zero `ud2` sentinels in `.text` (was 32 paired sentinels under the cycc 6.0.0 regression).

### Smoke

```
$ tests/ovmf_smoke.sh
PASS: "gnoboot v0.3.0: handing off to kernel" observed
```

End-to-end Path-C boot via `agnosticos/scripts/qemu-fb-smoke.sh` against `EXPECT="fb: mode="` also PASSES — the agnos kernel reads the new fields and emits `fb: mode=0/30 phys=0x80000000 pf=1 w=1920 h=1080 pitch=7680` on serial. Iron Attempt 72 (the two-boot VGA-spec vs Quiet Boot diff on archaemenid) is the next move; see `agnosticos/docs/development/iron-nuc-zen-log.md` § Attempt 72 prep.

## [0.2.0] — 2026-05-15

Iron-confirmed cleanup release. Booted to AGNOS shell on archaemenid (NUC AMD) under the cleanup-pass kernel; banner overlay is cosmetic only, handoff itself is verified. CMOS port-I/O diagnostic blocks moved to kernel-side `read-boot-log.sh` ground truth (kernel still stamps via raw asm); gnoboot becomes a slim handoff path with one tightened banner and shared failure-code surface.

### Changed

- **UEFI-output cleanup** (2026-05-15). Collapsed the 13 per-stage
  failure strings (`msg_li_f`, `msg_sfs_f`, … `msg_ebs_f`) into a
  single shared template `msg_fail = "gnoboot: fail @ XXXX\r\n"`
  plus a 13-entry `code_*` table. New `efi_fail(st, code)` helper
  patches the 4-char placeholder via one `store64` and prints — call
  sites went from `efi_print(st, &msg_XX_f); return 0;` to
  `efi_fail(st, &code_XX); return 0;`. ABI unchanged; binary stays
  within structural-gate envelope.

- **Banner tightened to `gnoboot v<VERSION>: handing off to kernel`**
  (2026-05-15). Drops the stale "step 7" framing carried over from
  the path-c bring-up. `tests/ovmf_smoke.sh` default `EXPECT` updated
  to match the new banner — the prior default
  (`gnoboot v0.1.0`) had silently diverged from the actual ConOut
  text and was failing on every run regardless of handoff correctness.
  Version string in `msg_pre` is hand-synced with `VERSION` at each
  release tag; release checklist updated to call this out.

- **Banner now lands on a cleared screen** (2026-05-15). Added
  `efi_clear(st)` helper (calls `ConOut->ClearScreen` via fncall1)
  invoked immediately before `efi_print(&msg_pre)`. Wipes the
  firmware splash + OVMF preamble so gnoboot's handoff line is the
  only thing on the framebuffer when control passes to the kernel.

### Removed

- **CMOS canary checkpoints** (2026-05-15). Stripped the five inline
  CMOS-port-I/O blocks at `efi_main` entry, post-`HandleProtocol`,
  post-ELF-load, pre-EBS, and post-EBS-immediately-pre-jmp. Each
  block wrote `CMOS[0x52] = <stage>` (and the entry block also wrote
  `CMOS[0x53] = 0xCD` as a presence magic) so a downstream Linux
  could `read-boot-log.sh` from battery-backed RTC RAM after a
  faulted reset. Diagnostic channel only — never load-bearing on the
  handoff. Boot-info struct ABI, magic (`0x41474E4F`), and
  RDI-convention all unchanged. GOP framebuffer capture is retained
  (v2 boot-info layout still inlines `fb_phys` / `fb_pitch` /
  `fb_width` / `fb_height` / `fb_pixel_format` at offsets 0x48-0x5C).

### Added

- **GOP framebuffer capture for Attempt 7 boot-canary** (2026-05-13).
  Attempt 6 on NUC AMD reproduced Attempt 5's symptom (step-7 line +
  blank + reset) — meaning the BSS-zero and EfiLoaderCode fixes below
  ran on iron and didn't change the outcome. Both highest-confidence
  hypotheses are ruled out; remaining hypotheses (inherited PT W^X,
  GDT divergence, CR0/CR4 state) can't be bisected without visibility
  into kernel-side execution, and no serial cable is yet attached.
  GOP capture lets the kernel's first instruction paint a visible
  canary stripe — see agnos `boot_shim.cyr` ELF64 path.

  Implementation: `LocateProtocol(EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID)`
  pre-EBS (Boot Service; must run before Step 12 `GetMemoryMap`
  refresh because any firmware call invalidates the map key).
  Copies `fb_phys`, `fb_pitch = ppl × 4`, `fb_width`, `fb_height`,
  `fb_pixel_format` from `gop->Mode` into inlined boot_info fields
  at offsets 0x48-0x5C. Pointers go dead post-EBS but the framebuffer
  physical base + geometry stay valid for the kernel's lifetime.
  Failure mode benign: if no GOP (text-mode/headless firmware),
  `fb_phys = 0` and the agnos canary's `JZ` skips the paint.

  Boot-info struct grows 80 → 112 bytes; version field bumps 1 → 2.
  Path-c doc § *Handoff protocol* updated to reflect the move from
  tag-stream (type=1) to inlined fields. Kernel walkers MUST NOT
  expect a framebuffer tag in the stream from v2 onward.

### Fixed

- **Iron-only triple-fault post-EBS** (gnoboot's first iron run —
  Attempt 5 / NUC AMD, 2026-05-13). Display showed "gnoboot 0.1 step 7:
  Jumping to kernel..." (cosmetically on the same line as the firmware
  splash because the splash didn't `\r\n`-terminate), then blank screen
  + reset. QEMU OVMF still booted the kernel through 17 init checkpoints
  to `Activating scheduler...` — divergence isolated to two gnoboot
  assumptions that held under OVMF but not under AMD Zen UEFI:
  1. **BSS gap not zeroed.** `main.cyr` read only `p_filesz` bytes
     into `p_paddr` and never zeroed `[p_filesz, p_memsz)` (64 KB for
     agnos 1.30.0). UEFI 2.x § 7.2 states `AllocatePages` returns
     undefined memory contents; QEMU OVMF happened to return zeroes,
     real firmware leaves POST/EFI scratch. Kernel `.bss` globals read
     garbage on iron, triple-fault at first reference. Fix: byte-loop
     `store8(addr, 0)` over the gap right after the segment read and
     ELF-magic verify. No new stdlib dep (gnoboot stays `[deps] stdlib = []`).
  2. **MemoryType 2 (EfiLoaderData) → 1 (EfiLoaderCode).** Strict-W^X
     firmware NX-marks LoaderData pages — jump to 0x1000A8 in a
     LoaderData page faults silently on iron; OVMF executes from
     LoaderData regardless. EfiLoaderCode tells firmware "this is
     executable" so NX stays clear in the inherited post-EBS page
     tables. One-byte change at the `bs->AllocatePages` call.

  Both fixes shipped in Attempt 6 — no improvement on iron (same
  symptom as Attempt 5). Hypotheses #1 and #2 ruled out; see *Added*
  above for the next bisection step.
  `tests/ovmf_smoke.sh` still PASS on QEMU OVMF (kernel reaches
  `Activating scheduler...`).
  Diagnosis logged in `agnosticos/docs/development/iron-nuc-zen-log.md`
  § *Attempt 5* and § *Attempt 6*.


## [0.1.0] — 2026-05-13

First gnoboot release. AGNOS sovereign UEFI bootloader, Cyrius-native,
replaces GRUB on the boot path. Loads the AGNOS kernel from the ESP,
builds a sovereign boot-info struct, calls `ExitBootServices`, jumps
to kernel entry with `RDI = &boot_info`.

Verified end-to-end on QEMU OVMF: gnoboot delivers the AGNOS kernel
through its boot_shim into kernel-side init (banner + 9 further
init lines through `Page tables: 1024MB mapped` print post-EBS).
Iron Attempt 5 on the NUC AMD is the remaining validation pass.

Brought forward to MVP-critical 2026-05-13 after GRUB's multiboot2-EFI
relocator was found to write to its own `.text` and fault under
modern strict-W^X UEFI (see `agnosticos/docs/development/iron-nuc-zen-log.md`
§ *Diagnosis 2 — 2026-05-13 GRUB relocator W^X* for the forensic
trail and `agnosticos/docs/development/path-c-sovereign-uefi.md` for
the plan).

### Added

- UEFI Application entry via cyrius 5.11.53's `fn efi_main(handle, st)`
  convention. Cyrius's auto-trampoline at `.text+0x339` saves the
  firmware-supplied `RCX` (ImageHandle) and `RDX` (SystemTable) into
  callee-saved `R14`/`R15`, runs gvar inits, restores into RCX/RDX,
  and calls `efi_main` with MS x64 ABI.
- ESP file access via `bs->HandleProtocol(handle, &LI_GUID)` →
  `bs->HandleProtocol(LI->DeviceHandle, &SFS_GUID)` →
  `sfs->OpenVolume` → `root->Open("\boot\agnos", READ, 0)` →
  `file->Read`. All five firmware calls via `lib/fnptr.cyr`'s
  MS-x64 `fncallN` branches (which fire under
  `CYRIUS_TARGET_EFI=1` via the v5.11.52 TARGET_WIN co-predefine).
- ELF64 kernel load: read 64-byte header, parse `e_phoff`, read
  56-byte PT_LOAD program header, `bs->AllocatePages(AllocateAddress,
  EfiLoaderData, pages, &p_paddr)` at the kernel's fixed
  `p_paddr = 0x100000`, `file->Read(file, &filesz, p_paddr)` writes
  segment data directly to physical memory. ELF-magic read-back
  verifies the load.
- Sovereign boot-info struct (80 bytes, layout in
  `agnosticos/docs/development/path-c-sovereign-uefi.md` § Handoff):
  magic `0x41474E4F ('AGNO')`, version 1, struct_size 80, memmap
  pointer/count/entsize, EFI SystemTable pointer, END tag at
  offset `0x48`. Built statically with a byte-array literal
  (cyrius 5.11.51) plus runtime `store32`/`store64` fills.
- `bs->GetMemoryMap` × 2 (informational + fresh-key right before
  EBS) into a 16 KB cyrius global buffer. The second call's
  `mm_key` is what `ExitBootServices(handle, mm_key)` requires.
- `bs->ExitBootServices(handle, mm_key)` — point of no return.
  After EBS, ConOut is gone; any further diagnostic is via the
  kernel's own COM1 UART output captured by QEMU `-serial stdio`.
- Inline-asm jump to kernel entry at `0x1000A8` with
  `RDI = &boot_info` (SysV arg 0): `mov rdi, rax; mov eax, 0x1000A8;
  jmp rax`. Cyrius's `var p = &boot_info` emits the
  `movabs rax, &boot_info` immediately before, leaving the
  destination in RAX for the asm.

### Tooling

- `tests/verify_pe.sh` — fast structural gate. Verifies DOS magic
  at 0x00, PE signature at 0x40, COFF Characteristics 0x0022 (no
  RELOCS_STRIPPED) at 0x56, Subsystem 0x000A (EFI_APPLICATION) at
  0x9C, DllCharacteristics NX_COMPAT bit set at 0x9E. Runs without
  QEMU.
- `tests/ovmf_smoke.sh` — runtime end-to-end gate. Builds a 64 MB
  GPT disk with ESP at 1 MiB, copies `build/BOOTX64.EFI` to
  `\EFI\BOOT\BOOTX64.EFI` and (optionally) the agnos kernel build
  to `\boot\agnos`, boots under qemu-system-x86_64 + OVMF, asserts
  the expected banner appears on the firmware ConOut serial.
  Cross-distro OVMF path probing (Arch `edk2-ovmf` + Ubuntu
  `ovmf`); graceful SKIP if `qemu-system-x86_64`, `parted`,
  `mtools`, or OVMF firmware files are missing.
- `.github/workflows/ci.yml` — installs cyrius (canonical
  `install.sh` + post-install smoke per the agnos pattern), builds
  with `CYRIUS_TARGET_EFI=1`, runs both gates on `ubuntu-latest`
  with `ovmf parted mtools qemu-system-x86` apt-installed, uploads
  `BOOTX64.EFI` as a build artifact.
- `.github/workflows/release.yml` — triggered on `v?X.Y.Z` tags.
  CI gate first; then version-verifies `VERSION` against the tag,
  builds, structural-gates, stages release artifacts
  (`BOOTX64.EFI` + `gnoboot-X.Y.Z-x86_64-efi.efi` + `SHA256SUMS`),
  publishes to a GitHub release with auto-generated notes via
  `softprops/action-gh-release@v2`.

### Cross-repo dependencies

- **cyrius 5.11.53** — pinned in `cyrius.cyml`. v0.1.0 specifically
  needs:
    - **5.11.51** — byte-array literal `var foo[N] = { 0x.., ... };`
    - **5.11.52** — `fn efi_main(handle, st)` convention + cyrius
      auto-predefines `CYRIUS_TARGET_WIN` alongside
      `CYRIUS_TARGET_EFI` (so `lib/fnptr.cyr`'s MS-x64 fncallN
      branches fire under TARGET_EFI).
    - **5.11.53** — hotfix for v5.11.52's entry-save REX prefix
      (was emitting `mov rsi, r9; mov rdi, r10` instead of
      `mov r14, rcx; mov r15, rdx` — gnoboot agent caught the bug
      hours after 5.11.52 ship; fix landed same-day).
- **agnos 1.30.0** — pairs with gnoboot v0.1.0. Kernel ABI break:
  entry contract switched from multiboot2's `RBX = MBI ptr` to
  sovereign-struct's `RDI = &boot_info`. The 3-byte asm change is
  in `kernel/arch/x86_64/mbi.cyr` (`mov [rax], rbx` →
  `mov [rax], rdi`); the kernel still just stashes the pointer,
  doesn't yet read it.

### Upstream issues filed

Gnoboot's bring-up surfaced four cyrius issues, three of which
landed in the v5.11.51–v5.11.53 cycle:

1. **UEFI Application emit mode** (filed → cyrius 5.11.49).
   Adds `_TARGET_EFI_APPLICATION` flag gated by
   `CYRIUS_TARGET_EFI=1`: PE32+ with subsystem 0xA, no Win32
   imports, populated `.reloc`, RELOCS_STRIPPED cleared.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-uefi-application-emit.md`.
2. **Byte-array literal syntax** (filed → cyrius 5.11.51).
   `var foo[N] = { 0x.., 0x.., ... };` for compile-time-known
   UTF-16LE strings, EFI GUIDs, sovereign-struct static init.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-byte-array-literal.md`.
3. **`fn efi_main(handle, st)` convention** (filed → cyrius 5.11.52).
   Auto-emits the firmware-entry trampoline. Cyrius scans `fn_names`
   for `efi_main\0` and emits save / restore / call sequence around
   the standard gvar-inits flow.
   `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-efi-main-convention.md`.
4. **cyrius-lsp byte-array-literal recognition** (filed; pending,
   candidate for 5.11.54+). LSP still emits a parse-error
   diagnostic on `var foo[N] = { ... }` even though `cc5` accepts
   it — likely the LSP wasn't rebuilt against the v5.11.51
   frontend. Diagnostic noise only; doesn't affect builds.
   `cyrius/docs/development/issues/2026-05-13-gnoboot-lsp-byte-array-literal.md`.

### Known limitations

- **AGNOS kernel stalls past `Page tables: 1024MB mapped`** under
  the UEFI + gnoboot boot path. Under the legacy
  `qemu-system-x86_64 -kernel` path the kernel reached
  `Memory isolation: PASS` / `Userland exec complete` /
  `KASLR: pmm_next_free=N`. The two paths differ in pre-handoff
  environment (UEFI's GDT + identity-mapped page tables + NX bits
  vs. the kernel's own boot-shim setup under `-kernel`). The
  kernel-side init survives 10 checkpoints — the stall is post-
  page-tables. Not a gnoboot bug: handoff is verified correct
  (banner + 9 lines print *after* `ExitBootServices`). Tracked in
  `agnos/docs/development/state.md` § *Open investigation — kernel
  hang post-page-tables under UEFI+gnoboot*; expected to land in
  the next agnos sub-arc.
- **Iron Attempt 5 (NUC AMD) not yet exercised.** v0.1.0 is verified
  on QEMU OVMF emulation only. The iron test path is full
  `scripts/install-usb.sh` re-provision (via the agnosticos repo)
  + NUC AMD reboot. Tracked in
  `agnosticos/docs/development/iron-nuc-zen-log.md`.
- **Cyrius-lsp diagnostic noise** on every save of `src/main.cyr`:
  `[Line 1:1] expected ';', got '='`. LSP is misreading the
  byte-array literal syntax; build is unaffected. Pending upstream
  rebuild (see *Upstream issues filed* #4).

### Development notes

A handful of bisection findings that drove the source's current
shape — useful for the next gnoboot contributor; not strict release
content.

- **Top-level `kernel;` mode emit order**: `var X = expr;` at the
  top level of a `kernel;` source is a *global with deferred
  initializer*, not an inline statement. Cyrius emits intervening
  `asm` blocks BEFORE the `&expr` lea, so the agnos-shim
  `var p = &foo; asm { mov [rax], rdx }` register-capture pattern
  silently fails at top level (RAX is junk; capture writes to
  random memory). The pattern works **inside a fn body** — locals
  ARE inline. gnoboot's "Step 4a probe" originally claimed PASS
  from this pattern; Step 4's disassembly later revealed the
  capture was a no-op and the post-capture print only worked
  because it used firmware-preserved RDX directly. After the
  cyrius 5.11.52 `fn efi_main` convention landed, the pattern
  became irrelevant — cyrius auto-emits the entry trampoline.
- **Cyrius internal fn-call ABI under `_TARGET_EFI_APPLICATION` is
  MS x64**, not SysV — verified via `objdump`. Callee prologue
  saves RCX/RDX (not RDI/RSI) to local slots. This contradicts
  `lib/fnptr.cyr`'s longstanding SysV comment, which predates the
  TARGET_EFI work. Under v5.11.52+ cyrius predefines
  `CYRIUS_TARGET_WIN` alongside `CYRIUS_TARGET_EFI` so the
  TARGET_WIN MS-x64 branches in `fnptr.cyr` fire — `fncallN` does
  the right thing under TARGET_EFI without per-target plumbing.
- **Byte-array literal `[N]` capacity** is `N × 8` bytes (cyrius's
  array-slot semantic). For UTF-16LE messages, `N = ceil((chars+1)*2 / 8)`.
  Cyrius reports overflow errors with a line number that points
  *near* — sometimes one or two lines before — the first
  overflowing array; not always the array itself. Two early
  overflows (`msg_li_fail` at 18 B in N=2=16 cap, `msg_sfs_fail`
  at 20 B) were misread as a different array failing because the
  reported line was a blank line. Re-look at the next overflow
  encountered.
- **OVMF requires GPT-disk-with-ESP** for the
  `\EFI\BOOT\BOOTX64.EFI` removable-boot path to resolve. A raw
  FAT image gets `BdsDxe: failed to load Boot0002: Not Found`.
  `tests/ovmf_smoke.sh` builds the canonical layout: 64 MB image
  + GPT label + single FAT32 ESP partition at 1 MiB + `esp on`
  flag.
- **`AllocatePages` at `AllocateAddress = 0x100000`** works under
  OVMF (firmware reserves below 1 MB but not at the 1 MB mark
  itself). `EfiLoaderData` MemoryType lets us write to the
  allocated pages during boot services time; W^X "no-execute"
  enforcement only bites at execution-time (didn't affect our
  load — and didn't affect the post-EBS jump to 0x1000A8 either,
  since the kernel ran far enough to print 10 init lines).
- **`ExitBootServices` map-key invalidation**: any firmware
  service call (including `efi_print` via ConOut) between
  `GetMemoryMap` and `ExitBootServices` invalidates the
  `mm_key`. gnoboot calls `GetMemoryMap` once informationally
  early, then re-calls it immediately before `ExitBootServices`
  with no intervening firmware calls. The fresh key passes.
