#!/bin/sh
# tests/verify_pe.sh — fast structural verification of build/BOOTX64.EFI.
#
# Checks the PE32+ header fields that determine whether UEFI firmware
# will accept the binary. Faster than tests/ovmf_smoke.sh (no QEMU
# spin-up); runs in CI even when OVMF/parted/mtools aren't installed.
#
# Verifies (per cyrius 5.11.49 UEFI emit + MS PE/COFF spec):
#   DOS magic  @ 0x00 = 4D 5A          ("MZ")
#   PE sig     @ 0x40 = 50 45 00 00    ("PE\0\0")
#   COFF Char  @ 0x56 = 22 00 LE       (0x0022 — EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE; NO RELOCS_STRIPPED)
#   Subsystem  @ 0x9C = 0A 00 LE       (0x000A — IMAGE_SUBSYSTEM_EFI_APPLICATION)
#   DllChar    @ 0x9E = 00 01 LE       (0x0100 — NX_COMPAT)
#
# Usage:
#   tests/verify_pe.sh                          # uses build/BOOTX64.EFI
#   tests/verify_pe.sh /path/to/BOOTX64.EFI     # custom binary

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EFI="${1:-$ROOT/build/BOOTX64.EFI}"

[ -f "$EFI" ] || { echo "ERROR: $EFI not found — run \`CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI\` first" >&2; exit 1; }
command -v xxd >/dev/null 2>&1 || { echo "ERROR: xxd required" >&2; exit 1; }

# Hex byte sequence extractor — strips the offset prefix and trailing
# ASCII gutter, lowercases. Returns the raw hex byte sequence.
read_bytes() {
    xxd -s "$1" -l "$2" "$EFI" | head -1 | awk '{
        out = ""
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^[0-9a-fA-F]+$/) out = out tolower($i)
        }
        # tolower leaves digits alone; strip any stray space too
        gsub(/ /, "", out)
        print out
    }'
}

assert_eq() {
    label="$1"; offset="$2"; length="$3"; expected="$4"
    actual="$(read_bytes "$offset" "$length")"
    # Normalize expected: strip spaces
    expected_norm="$(echo "$expected" | tr -d ' ')"
    if [ "$actual" = "$expected_norm" ]; then
        printf "  PASS: %-30s @ %s = %s\n" "$label" "$offset" "$actual"
    else
        printf "  FAIL: %-30s @ %s = %s (expected %s)\n" "$label" "$offset" "$actual" "$expected_norm"
        FAILED=1
    fi
}

FAILED=0
echo "structural gate: $EFI"

assert_eq "DOS magic"          0x00 2 "4d5a"
assert_eq "PE signature"       0x40 4 "50450000"
assert_eq "COFF Characteristics" 0x56 2 "2200"
assert_eq "Subsystem"          0x9c 2 "0a00"

# DllCharacteristics: NX_COMPAT (0x0100) must be set. Other bits are
# permitted — when the binary has base relocations, cyrius sets
# DYNAMIC_BASE (0x0040) + HIGH_ENTROPY_VA (0x0020) as well, giving
# 0x0160. A banner-only build (no relocs) shows the raw 0x0100.
# Either is fine.
dllc_bytes="$(read_bytes 0x9e 2)"
dllc_hi="$(echo "$dllc_bytes" | cut -c3-4)"     # high byte (LE: 2nd nibble pair)
case "$dllc_hi" in
    *[13579bdf]*)
        printf "  PASS: %-30s @ 0x9e = %s (NX_COMPAT set)\n" "DllCharacteristics" "$dllc_bytes"
        ;;
    *)
        printf "  FAIL: %-30s @ 0x9e = %s (NX_COMPAT bit 0x0100 not set; high byte = %s)\n" "DllCharacteristics" "$dllc_bytes" "$dllc_hi"
        FAILED=1
        ;;
esac

if [ "$FAILED" = "1" ]; then
    echo "structural gate: FAIL"
    exit 1
fi
echo "structural gate: PASS"
