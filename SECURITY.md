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
  oversized program-header counts, malformed or truncated PT_LOAD
  entries. Bounds-checked at parse time against the file's actual
  size; fail to a status print before EBS. **Implemented at v0.7.0**
  and exercised by `tests/malformed_kernel.sh`, which boots 18
  deliberately-corrupted kernels under OVMF and asserts the specific
  failure code for each.

  > **Historical accuracy.** This clause was published from v0.1.0 but
  > was **not true until v0.7.0**: `e_phnum` was never read, no
  > `PT_LOAD` field was bounds-checked, and the pre-load ELF check was
  > a single byte. The 2026-08-29 audit
  > ([`docs/audit/2026-08-29-audit.md`](docs/audit/2026-08-29-audit.md),
  > findings F1–F4) found the gap; v0.7.0 closed it. Recorded rather
  > than quietly corrected, because a threat model that overstates
  > coverage is worse than one that admits the gap — it stops the next
  > reader from looking.

- **Firmware-misreported sizes** — `GetMemoryMap` returning a size
  larger than our buffer (16 KB cap). Fail closed, do not silently
  truncate. *(Audit-verified sound, S2. The buffer is declared at
  exactly the size passed to firmware, so `EFI_BUFFER_TOO_SMALL` is
  returned and honored rather than the map being truncated into a
  short buffer.)*
- **Map-key invalidation** — any unintended firmware call between
  `GetMemoryMap` and `ExitBootServices` invalidates the snapshot.
  Path is straight-line in code; no helper functions between those
  two calls. *(Audit-verified sound, S1, line by line.)*
- **Firmware-supplied counts** — the EFI configuration-table entry
  count, the GOP mode count, and the memory-map descriptor size are
  each bounded before use, so a firmware reporting a nonsense value
  cannot drive an unbounded loop or a divide-by-zero pre-EBS.
  *(v0.7.0, audit F9.)*

**Fails loudly, not open**: when `RDRAND` cannot supply entropy for the
KASLR slide, gnoboot loads at a deterministic fallback base **and sets
`boot_info` flags bit 2** so the kernel can say so. Before v0.7.0 the
fallback base was indistinguishable at the kernel from a successful
randomization — the security property failed silently (audit F6).

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
`docs/audit/YYYY-MM-DD-audit.md`. **First pass: 2026-08-29** at v0.6.2
([`docs/audit/2026-08-29-audit.md`](docs/audit/2026-08-29-audit.md)) —
10 findings, 9 verified-sound paths; the code fixes shipped at v0.7.0.
Severity levels:

- **CRITICAL** — remote or local privilege escalation via a single
  reproducible step
- **HIGH** — moderate effort to exploit; bypasses an explicit
  security boundary
- **MEDIUM** — exploitable only under specific conditions
- **LOW** — defense-in-depth concerns, hardening opportunities
