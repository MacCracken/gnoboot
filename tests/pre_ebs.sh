#!/bin/sh
# tests/pre_ebs.sh — the v0.9.0 pre-ExitBootServices hardening gate.
#
# Three things were added at v0.9.0 that a normal boot cannot prove: a machine
# that fails the memory-map sanity check, a boot_info that fails its
# self-consistency check, and a memory map too big for the old 16 KB buffer.
# malformed_kernel.sh's reasoning applies: a check nothing exercises is
# indistinguishable from one that is absent.
#
#   RAM   QEMU can force this: a 64 MB guest has under 64 MB left once firmware
#         takes its share, and must stop at "fail @ RAM".
#   BI    Nothing external can corrupt boot_info, so this builds a copy of the
#         source that does, and asserts "fail @ BI".
#   grow  OVMF's map is far under 16 KB, so this builds a copy that fragments
#         memory first, and asserts the kernel still boots. The same copy stops
#         at "fail @ BI" if the map did not outgrow the old limit, because a case
#         that no longer reaches the condition must not keep passing.
#
# The copies are made by exact-text edits to src/main.cyr. An edit that no
# longer matches fails the gate, so reworded source cannot quietly retire a case.
# The real build/BOOTX64.EFI is only booted for the RAM case, and never modified.
#
# Usage:
#   tests/pre_ebs.sh
#   AGNOS_KERNEL=/path/to/agnos tests/pre_ebs.sh
#
# Exits 77 ("did not run", not a pass) when cyrius, python3, a kernel, or what
# ovmf_smoke.sh needs is absent.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_KERNEL="${AGNOS_KERNEL:-$ROOT/../agnos/build/agnos}"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not in PATH"; exit 77; }
command -v cyrius  >/dev/null 2>&1 || { echo "SKIP: cyrius not in PATH"; exit 77; }
[ -f "$SRC_KERNEL" ] || { echo "SKIP: no agnos kernel at $SRC_KERNEL"; exit 77; }

D=$(mktemp -d -t gnoboot-preebs.XXXXXX)
trap 'rm -rf "$D"' EXIT

FAILED=0

# mutant <name> <python body>
#   Builds a modified copy at $D/<name>/build/BOOTX64.EFI. The body calls
#   at(anchor, replacement), and each anchor must match exactly once.
mutant() {
    v="$D/$1"
    mkdir "$v"
    cp -r "$ROOT/src" "$ROOT/lib" "$ROOT/cyrius.cyml" "$ROOT/VERSION" "$v/"
    python3 - "$v/src/main.cyr" <<PYEOF
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
def at(anchor, new):
    global s
    if s.count(anchor) != 1:
        sys.exit(f"edit does not apply, {s.count(anchor)} matches: {anchor!r}")
    s = s.replace(anchor, new)
$2
open(p, 'w', encoding='utf-8').write(s)
PYEOF
    mkdir "$v/build"
    ( cd "$v" && CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI ) >"$v/build.log" 2>&1 || {
        echo "FAIL: variant $1 did not build"
        tail -5 "$v/build.log"
        exit 1
    }
}

# expect <label> <marker> <deadline> <efi>
expect() {
    printf '  %-8s expect "%s" ... ' "$1" "$2"
    rc=0
    AGNOS_KERNEL="$SRC_KERNEL" EXPECT="$2" QEMU_TIMEOUT="$3" \
        "$ROOT/tests/ovmf_smoke.sh" "$4" >"$D/log" 2>&1 || rc=$?
    case "$rc" in
        0)
            echo "PASS"
            ;;
        77)
            echo "SKIP"
            sed -n '1p' "$D/log"
            exit 77
            ;;
        *)
            echo "FAIL"
            sed -n '1,25p' "$D/log" | sed 's/^/    /'
            FAILED=1
            ;;
    esac
}

echo "pre-EBS gate: $SRC_KERNEL"

QEMU_MEM=64M expect RAM "gnoboot: fail @ RAM" "${QEMU_TIMEOUT:-20}" "$ROOT/build/BOOTX64.EFI"

mutant bi '
at("    if (boot_info_sane() == 0) {",
   "    store32(&boot_info + 0x08, 0x78);\n    if (boot_info_sane() == 0) {")
'
expect BI "gnoboot: fail @ BI" "${QEMU_TIMEOUT:-20}" "$D/bi/build/BOOTX64.EFI"

# Alternating memory types stop adjacent single pages merging into one descriptor.
mutant grow '
at("    # --- 11: Size the memory map, allocate for it, take a first copy ---\n",
   "    var frag = 0;\n"
   "    while (frag < 400) {\n"
   "        store64(&alloc_addr, 0);\n"
   "        fncall4(fn_alloc, 0, 2 + (frag % 2) * 2, 1, &alloc_addr);\n"
   "        frag = frag + 1;\n"
   "    }\n"
   "    # --- 11: Size the memory map, allocate for it, take a first copy ---\n")
at("    store32(&boot_info + 0x34, dsz);                   # memmap_entsize\n",
   "    store32(&boot_info + 0x34, dsz);                   # memmap_entsize\n"
   "    if (sz <= 16384) { efi_fail(st, &code_bi); return 0; }\n")
'
expect grow "Launching kybernet" "${QEMU_TIMEOUT:-60}" "$D/grow/build/BOOTX64.EFI"

[ "$FAILED" -eq 0 ] || { echo "pre-EBS gate: FAIL"; exit 1; }
echo "pre-EBS gate: PASS"
