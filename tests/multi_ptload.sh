#!/bin/sh
# tests/multi_ptload.sh — the v0.7.0 multi-PT_LOAD positive gate (roadmap M5,
# audit finding F2).
#
# Before v0.7.0 gnoboot read exactly ONE program header and hard-failed if it
# was not PT_LOAD. A kernel with two PT_LOAD segments was SILENTLY
# under-loaded — only the first landed, and gnoboot jumped into a partial
# image. Nothing caught that, because agnos happens to link as a single
# PT_LOAD, so the happy-path gates stayed green over a latent bug.
#
# The test: take the real agnos kernel and SPLIT its single PT_LOAD into two
# contiguous ones, appending a fresh 2-entry program-header table at the end
# of the file and re-pointing e_phoff at it. Not one byte of kernel code or
# data changes, and the two segments describe exactly the same physical
# layout the single one did — so a correct loader must produce a
# byte-identical memory image and the kernel must boot exactly as it does
# unmodified.
#
# That equivalence is the whole point: a loader that mishandles the second
# segment produces a kernel that is subtly wrong rather than obviously
# broken, which is precisely the failure this gate is here to catch.
#
# Both the unmodified and the split kernel are booted, and the same marker is
# asserted for each — so an environmental failure reports as "baseline
# failed" instead of being misattributed to the split.
#
# NOT covered here: the ET_DYN / KASLR path. agnos currently links ET_EXEC,
# and gnoboot's PIE branch (including the multi-segment span allocation)
# needs a real PIE kernel to exercise. See docs/development/state.md § Open.
#
# Usage:
#   tests/multi_ptload.sh
#   AGNOS_KERNEL=/path/to/agnos tests/multi_ptload.sh

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_KERNEL="${AGNOS_KERNEL:-$ROOT/../agnos/build/agnos}"
# A marker deep enough to prove the WHOLE image landed, not just the entry
# page — kybernet launches after the scheduler is live.
MARKER="${MARKER:-Launching kybernet}"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not in PATH"; exit 0; }
[ -f "$SRC_KERNEL" ] || {
    echo "SKIP: no agnos kernel at $SRC_KERNEL — this gate splits a real ELF64"
    exit 0
}

D=$(mktemp -d -t gnoboot-multiph.XXXXXX)
trap 'rm -rf "$D"' EXIT

echo "multi-PT_LOAD gate: $SRC_KERNEL"

python3 - "$SRC_KERNEL" "$D/agnos.split" <<'PYEOF'
import struct, sys

d = bytearray(open(sys.argv[1], 'rb').read())
e_phoff     = struct.unpack_from('<Q', d, 32)[0]
e_phentsize = struct.unpack_from('<H', d, 54)[0]
e_phnum     = struct.unpack_from('<H', d, 56)[0]
if e_phentsize != 56:
    sys.exit(f"unexpected e_phentsize {e_phentsize}")

loads = []
for i in range(e_phnum):
    o = e_phoff + i * 56
    if struct.unpack_from('<I', d, o)[0] == 1:
        loads.append(struct.unpack_from('<QQQQQ', d, o + 8))   # off, vaddr, paddr, filesz, memsz
if len(loads) != 1:
    sys.exit(f"expected exactly 1 PT_LOAD to split, found {len(loads)}")

off, vaddr, paddr, filesz, memsz = loads[0]
# Split on a page boundary at/below the halfway mark of the file image, so
# both halves carry real content and the second starts page-aligned.
cut = (filesz // 2) & ~0xFFF
if cut == 0 or cut >= filesz:
    sys.exit(f"segment too small to split (filesz=0x{filesz:x})")

seg = [
    # type, flags, off,       vaddr,        paddr,        filesz,        memsz
    (1, 5, off,       vaddr,       paddr,       cut,          cut),
    (1, 6, off + cut, vaddr + cut, paddr + cut, filesz - cut, memsz - cut),
]
# Sanity: the split must describe the identical byte and memory extents.
assert seg[0][5] + seg[1][5] == filesz
assert seg[0][6] + seg[1][6] == memsz
assert seg[1][4] == paddr + cut

new_phoff = len(d)                       # append the table past the loaded image
for t, fl, o, va, pa, fsz, msz in seg:
    d += struct.pack('<IIQQQQQQ', t, fl, o, va, pa, fsz, msz, 0x1000)
struct.pack_into('<Q', d, 32, new_phoff)
struct.pack_into('<H', d, 56, len(seg))

open(sys.argv[2], 'wb').write(d)
print(f"  split PT_LOAD 0x{paddr:x}+0x{memsz:x} into "
      f"0x{seg[0][4]:x}+0x{seg[0][6]:x} and 0x{seg[1][4]:x}+0x{seg[1][6]:x}")
print(f"  program-header table moved to file offset {new_phoff}, e_phnum=2")
PYEOF

run_case() {
    label="$1"; kernel="$2"
    printf '  %-24s expect "%s" ... ' "$label" "$MARKER"
    if AGNOS_KERNEL="$kernel" EXPECT="$MARKER" QEMU_TIMEOUT="${QEMU_TIMEOUT:-25}" \
       "$ROOT/tests/ovmf_smoke.sh" >"$D/log" 2>&1; then
        echo "PASS"
        return 0
    fi
    echo "FAIL"
    sed -n '1,25p' "$D/log" | sed 's/^/    /'
    return 1
}

if ! run_case "baseline (1 PT_LOAD)" "$SRC_KERNEL"; then
    echo "multi-PT_LOAD gate: BASELINE FAILED — environment problem, not the split"
    exit 1
fi
if ! run_case "split (2 PT_LOAD)" "$D/agnos.split"; then
    echo "multi-PT_LOAD gate: FAIL — the split image did not boot equivalently"
    exit 1
fi

echo "multi-PT_LOAD gate: PASS"
