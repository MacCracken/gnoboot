# Security Policy

gnoboot is the AGNOS sovereign UEFI bootloader. It runs in **boot
services context** — pre-kernel, with full UEFI firmware privileges,
no MMU isolation between it and the firmware. Security implications
of a gnoboot compromise are severe: an attacker who can substitute
or modify gnoboot can boot a kernel of their choice, with whatever
boot-info struct they want, on a machine that the firmware trusts.

## Threat model

gnoboot defends against:

- **Malformed kernel files** — `\boot\agnos` with bad ELF headers,
  oversized program-header counts, malformed PT_LOAD entries.
  Bounds-checked at parse time; fail to a status print before EBS.
- **Firmware-misreported sizes** — `GetMemoryMap` returning a size
  larger than our buffer (16 KB cap). Fail closed, do not silently
  truncate.
- **Map-key invalidation** — any unintended firmware call between
  `GetMemoryMap` and `ExitBootServices` invalidates the snapshot.
  Path is straight-line in code; no helper functions between those
  two calls.

gnoboot does **not** (currently) defend against:

- **Modified gnoboot binary** — pre-Secure-Boot, anyone with ESP
  write access can substitute `\EFI\BOOT\BOOTX64.EFI`. v0.x defers
  to UEFI Secure Boot (when enabled) for binary signing; post-v1
  may integrate signed boot directly.
- **Modified kernel binary** — gnoboot loads `\boot\agnos` without
  verifying a signature. v0.x relies on filesystem trust + Secure
  Boot's chain. Future TPM-measured-boot work is post-v1.
- **Firmware compromise** — gnoboot trusts UEFI Boot Services'
  return values. A compromised firmware can lie about memmaps,
  file contents, or function pointers. AGNOS doesn't have a
  defense against this layer today.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository, or
email the AGNOS project lead directly. Do **not** open a public
issue for a vulnerability before it's mitigated.

What to include:

1. **Reproduction**: minimal steps to trigger the issue. ESP layout,
   kernel binary state, firmware version (OVMF / vendor / real iron).
2. **Impact**: what an attacker gains. Boot-of-arbitrary-kernel?
   Firmware service exploitation? Information disclosure?
3. **Suggested mitigation** if you have one. Optional but speeds
   the fix.

## Disclosure timeline

- Acknowledgment: within 7 days of receipt.
- Initial assessment: within 14 days.
- Fix or status update: within 30 days for HIGH/CRITICAL; 60 days
  for MEDIUM; lower-severity issues queued normally.
- Coordinated public disclosure after the fix lands in a tagged release.

## Audit cadence

Per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md),
every gnoboot release runs an audit pass. Findings land in
`docs/audit/YYYY-MM-DD-audit.md` (earned at v0.5 or whenever the
first audit finishes). Severity levels:

- **CRITICAL** — remote or local privilege escalation via a single
  reproducible step
- **HIGH** — moderate effort to exploit; bypasses an explicit
  security boundary
- **MEDIUM** — exploitable only under specific conditions
- **LOW** — defense-in-depth concerns, hardening opportunities
