#!/bin/sh
# tests/build_pie_agnos.sh — build a PIE agnos kernel for tests/kaslr.sh.
#
# The agnos release asset is ET_EXEC, so the KASLR gate needs a kernel built
# with CYRIUS_PIE=1. Doing that by hand has three traps, all handled here:
#
#   - agnos's build writes build/agnos, the ET_EXEC kernel the other local gates
#     boot. This works on COPIES of agnos and its two sibling deps, inside a new
#     directory under gnoboot's build/, and nothing outside it is touched.
#   - agnos refuses a toolchain other than its pin, and the usual answers either
#     change the system default or build with the wrong compiler. CYRIUS_HOME
#     points this one build at the pinned install instead.
#   - agnos's build.sh exits 1 AFTER a good link, because its post-link check
#     expects the ET_EXEC entry 0x1000a8 and a PIE image's is 0xa8. So its exit
#     status says nothing here: success means an ET_DYN file came out.
#
# Progress and errors go to stderr; stdout is only the kernel's path.
#
# Usage:
#   AGNOS_PIE_KERNEL="$(tests/build_pie_agnos.sh)" tests/kaslr.sh
#   SIBLINGS_ROOT=/path/to/repos tests/build_pie_agnos.sh

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIB="${SIBLINGS_ROOT:-$ROOT/..}"

[ -f "$SIB/agnos/cyrius.cyml" ] || { echo "ERROR: no agnos checkout at $SIB/agnos" >&2; exit 1; }
PIN="$(sed -n 's/^cyrius *= *"\([^"]*\)".*/\1/p' "$SIB/agnos/cyrius.cyml" | head -1)"
TC="$HOME/.cyrius/versions/$PIN"
[ -x "$TC/bin/cyrius" ] || { echo "ERROR: agnos pins cyrius $PIN, not installed at $TC" >&2; exit 1; }

mkdir -p "$ROOT/build"
D="$(mktemp -d "$ROOT/build/agnos-pie.XXXXXX")"

for r in agnos kashi rekha; do
    [ -d "$SIB/$r" ] || { echo "ERROR: no $r checkout at $SIB/$r" >&2; exit 1; }
    mkdir "$D/$r"
    ( cd "$SIB/$r" && tar --exclude=.git --exclude=./build --exclude=.claude -cf - . ) | tar -xf - -C "$D/$r"
done
mkdir -p "$D/agnos/build"

echo "building PIE agnos with cyrius $PIN in $D" >&2
( cd "$D/agnos" && CYRIUS_HOME="$TC" CYRIUS_PIE=1 sh scripts/build.sh ) > "$D/build.log" 2>&1 || true

KERNEL="$D/agnos/build/agnos"
e_type="$(od -An -tx1 -j16 -N2 "$KERNEL" 2>/dev/null | tr -d ' \n')"
if [ "$e_type" != "0300" ]; then
    echo "ERROR: no ET_DYN kernel produced (e_type=${e_type:-none}); end of $D/build.log:" >&2
    tail -8 "$D/build.log" >&2
    exit 1
fi

echo "$KERNEL"
