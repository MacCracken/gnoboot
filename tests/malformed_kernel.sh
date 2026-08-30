#!/bin/sh
# tests/malformed_kernel.sh — the v0.7.0 ELF-load hardening regression gate.
#
# Proves that a malformed or truncated \boot\agnos FAILS TO A 4-CHAR CODE ON
# ConOut BEFORE ExitBootServices, rather than being loaded and jumped into.
# That is the entire promise of the v0.7.0 hardening (audit findings F1-F4,
# docs/audit/2026-08-29-audit.md) and the one SECURITY.md § Threat model has
# claimed since v0.1.0 without it being true.
#
# Why this gate has to exist: verify_pe.sh and ovmf_smoke.sh both test the
# HAPPY path. Before this script, every bounds check added at v0.7.0 was
# unexercised code — and an unexercised check is indistinguishable from an
# absent one. A regression that dropped any of them would leave both existing
# gates green.
#
# Mechanism: mutate a copy of the real agnos kernel one field at a time, then
# reuse tests/ovmf_smoke.sh via its AGNOS_KERNEL + EXPECT env hooks. No disk
# or QEMU logic is duplicated here — if the smoke harness changes, this
# follows automatically.
#
# Usage:
#   tests/malformed_kernel.sh                    # uses ../agnos/build/agnos
#   AGNOS_KERNEL=/path/to/agnos tests/malformed_kernel.sh
#
# Requires: python3, plus everything ovmf_smoke.sh requires (it SKIPs
# gracefully when QEMU/OVMF tooling is absent, and so does this).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_KERNEL="${AGNOS_KERNEL:-$ROOT/../agnos/build/agnos}"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not in PATH"; exit 0; }
[ -f "$SRC_KERNEL" ] || {
    echo "SKIP: no agnos kernel at $SRC_KERNEL — this gate mutates a real ELF64"
    echo "      (a synthetic 4-byte stub cannot exercise program-header parsing)"
    exit 0
}

D=$(mktemp -d -t gnoboot-malformed.XXXXXX)
trap 'rm -rf "$D"' EXIT

PASS=0
FAIL=0

# mutate <name> <expected-4-char-code> <python-mutation-body>
#   The body runs with `d` as a bytearray of the kernel and must modify it
#   in place. Structural offsets are ELF64 spec: e_ident at 0, e_type 16,
#   e_machine 18, e_phoff 32, e_phentsize 54, e_phnum 56.
mutate() {
    name="$1"; code="$2"; body="$3"
    out="$D/agnos.$name"
    python3 - "$SRC_KERNEL" "$out" <<PYEOF
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
e_phoff     = struct.unpack_from('<Q', d, 32)[0]
e_phentsize = struct.unpack_from('<H', d, 54)[0]
e_phnum     = struct.unpack_from('<H', d, 56)[0]
ph0 = e_phoff                       # first program header
$body
open(sys.argv[2], 'wb').write(d)
PYEOF
    printf '  %-22s expect "%s" ... ' "$name" "$code"
    if AGNOS_KERNEL="$out" EXPECT="gnoboot: fail @ $code" QEMU_TIMEOUT="${QEMU_TIMEOUT:-12}" \
       "$ROOT/tests/ovmf_smoke.sh" >"$D/log.$name" 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        echo "    ---- ConOut ----"
        sed -n '1,12p' "$D/log.$name" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

echo "malformed-kernel gate: $SRC_KERNEL"
echo "  (each case boots QEMU+OVMF once; expect ~10s per case)"

# --- F1: the ELF identity gate --------------------------------------------
# Each of these used to sail past the old one-byte `!= 0x7F` check and drive
# AllocatePages + Read from whatever the garbage headers said.
mutate bad-magic      "ELF " 'd[1] = 0x58'                                    # "\x7FXLF"
mutate bad-class      "ELF " 'd[4] = 1'                                       # ELFCLASS32
mutate bad-data       "ELF " 'd[5] = 2'                                       # ELFDATA2MSB
mutate bad-type       "ELF " 'struct.pack_into("<H", d, 16, 1)'               # ET_REL
mutate bad-machine    "ELF " 'struct.pack_into("<H", d, 18, 0x28)'            # EM_ARM
# e_type read as a full u16: 0x0102 has low byte 2 (ET_EXEC) and must still
# reject. The pre-v0.7.0 load8 would have accepted this.
mutate type-high-byte "ELF " 'struct.pack_into("<H", d, 16, 0x0102)'

# --- F1/F2: the program-header table bounds -------------------------------
mutate phnum-zero     "PHN " 'struct.pack_into("<H", d, 56, 0)'
mutate phnum-huge     "PHN " 'struct.pack_into("<H", d, 56, 4096)'            # > PH_MAX (16)
mutate phentsize-bad  "PHN " 'struct.pack_into("<H", d, 54, 32)'              # not 56
mutate phoff-past-eof "PHN " 'struct.pack_into("<Q", d, 32, len(d) + 1)'
mutate phoff-overlap  "PHN " 'struct.pack_into("<Q", d, 32, 8)'               # inside the ELF header

# --- F2: no loadable segment ----------------------------------------------
mutate no-pt-load     "PT  " 'struct.pack_into("<I", d, ph0, 4)'              # PT_NOTE, not PT_LOAD

# --- F4: the segment bounds -----------------------------------------------
# filesz > memsz is the copy overrun: pages are sized from memsz, then filesz
# bytes are Read into them.
mutate filesz-gt-memsz "SZ  " '''
memsz = struct.unpack_from("<Q", d, ph0 + 40)[0]
struct.pack_into("<Q", d, ph0 + 32, memsz + 0x10000)'''
# memsz just under 2**64 wrapped (memsz + 0xFFF) / 0x1000 to ZERO pages.
mutate memsz-wrap      "SZ  " 'struct.pack_into("<Q", d, ph0 + 40, 0xFFFFFFFFFFFFF800)'
mutate memsz-over-cap  "SZ  " 'struct.pack_into("<Q", d, ph0 + 40, 0x20000000)'   # > 256 MB
mutate paddr-over-cap  "SZ  " 'struct.pack_into("<Q", d, ph0 + 24, 0x40000000)'   # > 256 MB
mutate offset-past-eof "SZ  " 'struct.pack_into("<Q", d, ph0 + 8, len(d) + 1)'
# The truncated-kernel case — the realistic non-adversarial trigger this whole
# release exists for: an interrupted dd, a bad USB write, a failed ISO build.
# The header still claims the full filesz; the bytes are simply not there.
mutate truncated       "SZ  " 'del d[len(d)//2:]'

echo
echo "malformed-kernel gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "malformed-kernel gate: PASS"
