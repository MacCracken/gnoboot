# gnoboot — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> module sizes, supported targets, test counts, in-flight work, consumers)
> lives in [`docs/development/state.md`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**gnoboot** (no-frills boot) — AGNOS sovereign UEFI bootloader. Replaces
GRUB on the AGNOS boot path.

- **Type**: Binary (UEFI Application)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- **Path C plan**: [agnosticos/docs/development/path-c-sovereign-uefi.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/path-c-sovereign-uefi.md)

## Goal

**Own the AGNOS boot path.** UEFI firmware to AGNOS kernel entry, with
a sovereign-struct handoff (`RDI = &boot_info`, magic `0x41474E4F = 'AGNO'`).
No GRUB. No multiboot2 dependency on third-party loaders. Single
PE32+ EFI Application that loads, validates, and hands off the kernel.

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, binary size, test counts, in-flight work, consumers.
> Refreshed every release. This file (`CLAUDE.md`) is durable rules.

## Scaffolding

Project was scaffolded with `cyrius init gnoboot`. **Do not manually
create project structure** — use the tools. If a tool is missing
something, fix the tool.

## Quick Start

```sh
CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI
tests/verify_pe.sh                # fast structural gate (PE header)
tests/ovmf_smoke.sh               # runtime: qemu+OVMF banner check
```

## Key Principles

- **Sovereignty over compatibility** — gnoboot is the boot path, not
  *a* boot path. We don't accommodate other bootloaders; we replace
  them. (See ADR 0001.)
- **Handoff contract is sacred** — magic `0x41474E4F`, RDI = struct ptr,
  versioned. Changing the contract is a major version bump.
- **Correctness over cleverness** — if it boots wrong, the kernel
  crashes silently after EBS with no console. Verify before EBS.
- **Test under OVMF + iron** — emulation isn't always the same as
  firmware (the GRUB W^X blocker is one example of why).
- **Every cyrius build with `CYRIUS_TARGET_EFI=1`** — without it,
  cyrius emits Windows CUI (subsystem 3), which UEFI firmware rejects.
- **Build with `cyrius build`, not raw `cat | cc5`** — the manifest
  auto-resolves deps and prepends includes.
- **Buffer arrays are u64 slots**: `var foo[N]` = N × 8 **bytes**, not N
  bytes. Sizing UTF-16LE strings: `N = ceil((chars+1)*2 / 8)`.

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API only
- Do not skip the structural gate (`tests/verify_pe.sh`) before claiming a build works — UEFI rejects malformed PE silently
- Do not skip the OVMF gate before claiming a boot works — `grub-file --is-x86-multiboot2` passing does NOT mean the binary boots
- Do not call firmware boot services between `GetMemoryMap` and `ExitBootServices` — invalidates the map_key, EBS fails with `EFI_INVALID_PARAMETER`
- Do not bump the handoff struct magic or layout without bumping the major version — agnos kernel asserts compatibility via the magic
- Do not assume firmware-supplied registers (RCX/RDX) survive across cyrius's gvar inits — capture them in `fn efi_main(handle, st)` (cyrius 5.11.52+ auto-trampoline)
- Do not modify `lib/` files (vendored stdlib / dep symlinks)
- Do not hardcode cyrius versions in CI YAML — the `cyrius = "X.Y.Z"` pin in `cyrius.cyml` is the source of truth

## Process

### Work Loop (continuous)

1. **Work phase** — features, roadmap items, bug fixes
2. **Build check** — `CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI`
3. **Structural gate** — `tests/verify_pe.sh`
4. **OVMF runtime gate** — `tests/ovmf_smoke.sh`
5. **Documentation** — CHANGELOG entry, `docs/development/state.md` bump, ADR if a non-trivial design choice was made
6. **Version sync** — `VERSION`, `cyrius.cyml`, CHANGELOG header all match before tagging
7. **Return to step 1**

### Major Cycle Retrospective

At every major version bump (v1.0.0, v2.0.0, …) write a retrospective in `docs/development/retro/vN_cycle.md` capturing what shipped, what worked, what didn't (first time), what the cycle taught, and what carries into the next major. Pattern + template: [agnosticos retro pattern](https://github.com/MacCracken/agnosticos/blob/main/docs/development/retro/README.md).

### Release Checklist

```
[ ] tests/verify_pe.sh PASS
[ ] tests/ovmf_smoke.sh PASS (expect = current version banner)
[ ] VERSION updated
[ ] CHANGELOG.md updated, includes the new VERSION as a top-level section
[ ] cyrius.cyml toolchain pin matches the intended cyrius release
[ ] docs/development/state.md bumped
[ ] Git tag matches VERSION
[ ] CI passes on tag push
[ ] If major bump: docs/development/retro/vN_cycle.md drafted before tag
```

## Cyrius Conventions (gnoboot-specific)

- `fn efi_main(handle, st)` is the entry — cyrius 5.11.52+ auto-emits the trampoline
- `include "lib/fnptr.cyr"` — `fncallN` does the MS x64 ABI dance for firmware calls (TARGET_WIN branch fires under TARGET_EFI per cyrius 5.11.52)
- Byte-array literal `var foo[N] = { 0x.., 0x.. };` for UTF-16LE strings + EFI GUIDs (cyrius 5.11.51+)
- Inline asm only at the firmware-call boundary (when no `fncallN` arity covers it) or for the final `jmp` to kernel entry — never for control flow or string handling

## Docs

- [`docs/standards/handoff-protocol.md`](docs/standards/handoff-protocol.md) — **the handoff contract** (authoritative; the struct layout lives here and nowhere else)
- [`docs/audit/`](docs/audit/) — security / hardening audit passes
- [`docs/adr/`](docs/adr/) — architecture decision records (*why X over Y?*)
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints (*what's true about the code?*)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos
- [`docs/examples/`](docs/examples/) — runnable examples
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — milestones through v1.0 and post-v1
- [`docs/development/retro/`](docs/development/retro/) — per-major-version retrospectives (earned at v1.0 cut)

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Breaking changes (handoff struct layout, magic, register convention) get a **Breaking** section with migration guide. Security fixes get a **Security** section.
