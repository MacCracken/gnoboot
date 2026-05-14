# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot
derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides
(those live in [`../guides/`](../guides/)). An item here describes
*how the world is*, not *what we chose* or *how to do something*.

## Items

| # | Title | Subject |
|---|---|---|
| [001](001-sovereign-handoff-contract.md) | Sovereign handoff contract | RDI = &boot_info + magic + post-EBS register state |
| [002](002-ovmf-gpt-esp-required.md) | OVMF requires GPT-disk-with-ESP | Raw FAT images get `BdsDxe: Not Found` |
| [003](003-ms-x64-firmware-call-abi.md) | Cyrius MS x64 ABI under TARGET_EFI | Why `lib/fnptr.cyr`'s TARGET_WIN branch fires + the `-cpu max` requirement under QEMU |
