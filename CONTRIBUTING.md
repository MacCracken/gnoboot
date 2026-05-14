# Contributing to gnoboot

gnoboot is part of the AGNOS first-party application family.
Conventions and workflows are pinned in
[agnosticos's first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md);
this doc is the gnoboot-specific shape.

## Before changing anything

Read these in order:

1. [`README.md`](README.md) — what gnoboot is.
2. [`CLAUDE.md`](CLAUDE.md) — durable rules + the work loop.
3. [`docs/development/state.md`](docs/development/state.md) — current
   version, tested cyrius pin, known limitations.
4. [`docs/development/roadmap.md`](docs/development/roadmap.md) — what's
   slotted, what's out of scope. **Don't bring in v1.0 features in
   v0.x patches unless the roadmap says so.**

## The work loop

Every change follows the same loop:

1. **Build**: `CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI`
2. **Structural gate**: `tests/verify_pe.sh`
3. **OVMF runtime gate**: `tests/ovmf_smoke.sh`
4. **Documentation**: CHANGELOG entry, `docs/development/state.md`
   bump if version or surface changed, ADR if a non-trivial choice
   was made
5. **Version sync**: `VERSION` + `cyrius.cyml` + CHANGELOG header
   all match before the user tags a release

Skipping the gates is not acceptable. The structural gate runs in
~1 second; the OVMF gate in ~5 seconds (or 15 with a real kernel
under load). There's no excuse for "I'll test later."

## What earns an ADR

- Choosing one approach over another when a future reader might
  reasonably ask "why X and not Y?"
- Accepting or rejecting a cross-cutting dependency
- Designing a new layout for the sovereign boot-info struct
- Changing the handoff register convention (this is also a **major
  version bump**, not just an ADR)

Use [`docs/adr/template.md`](docs/adr/template.md) as the starting
point. Number sequentially (`0001-*.md`, `0002-*.md`, …). Never
renumber.

## What earns an architecture note

Anything a future reader can't derive from the code alone but
needs to know to read the code safely. Examples already in
[`docs/architecture/`](docs/architecture/):

- The handoff register/struct contract (001)
- OVMF's GPT-disk-with-ESP requirement (002)
- Cyrius's MS x64 ABI under TARGET_EFI (003)

These are observations about *the world the code lives in*, not
decisions about how we wrote it. Number sequentially. Never
renumber.

## What does NOT earn a new doc

- Bug fixes — CHANGELOG entry only
- Refactors that don't change behavior — CHANGELOG entry only
- New tests — covered by the gate scripts
- Cyrius version bumps — `cyrius.cyml` + CHANGELOG entry; if the
  bump unblocks something material, an ADR is fine, but routine
  bumps don't need one

## Cross-repo coordination

gnoboot has tight coupling to two siblings:

- **[cyrius](https://github.com/MacCracken/cyrius)** — the
  toolchain. When gnoboot needs a cyrius feature, file an issue
  in `cyrius/docs/development/issues/YYYY-MM-DD-<slug>.md` with a
  precise reproduction. Don't edit cyrius from gnoboot's side —
  cyrius has its own agents.
- **[agnos](https://github.com/MacCracken/agnos)** — the kernel.
  gnoboot v0.X pairs with agnos 1.Y; bump in lockstep when the
  handoff contract changes. agnos's CI pulls the gnoboot release
  asset.

## Hard constraints (from [`CLAUDE.md`](CLAUDE.md))

- Do not commit or push — the user handles all git operations
- Never use `gh` CLI — `curl` to the GitHub API only
- Do not skip the gates before claiming work is done
- Do not call firmware boot services between `GetMemoryMap` and
  `ExitBootServices` — invalidates the map_key
- Do not bump the handoff struct magic or layout without bumping
  the major version
- Do not hardcode toolchain versions in CI YAML — `cyrius.cyml` is
  the source of truth

## License

Contributions are accepted under [GPL-3.0-only](LICENSE) — the
AGNOS family default.
