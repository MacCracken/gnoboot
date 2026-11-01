#!/bin/sh
# tests/kaslr.sh — the ET_DYN / KASLR runtime gate.
#
# No gnoboot gate ran the PIE branch before v0.8.3: agnos links ET_EXEC by
# default, so every other gate takes the fixed-address path. This boots a real
# PIE kernel and asserts that each boot lands inside gnoboot's slide window,
# 2 MB-aligned, that the kernel runs to the scheduler from there, and that the
# base actually varies between boots.
#
# What this cannot see: the base comes from the kernel echoing boot_info+0x70.
# A gnoboot that loaded the image at one address and reported another would
# pass here. The address itself was confirmed through the QEMU monitor at
# v0.8.3 (see docs/development/state.md § Verified); this gate guards the slide.
#
# Boots take the full deadline, because QEMU never exits by itself. The default
# is long because a loaded host took 27s where an idle one takes 8s.
#
# Not run in CI: the agnos release asset is ET_EXEC. This is a release-cut gate.
#
# Usage:
#   AGNOS_PIE_KERNEL="$(tests/build_pie_agnos.sh)" tests/kaslr.sh
#
# Exits 77 ("did not run", not a pass) with no PIE kernel, or when ovmf_smoke.sh
# cannot run.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${AGNOS_PIE_KERNEL:-}"
MARKER="${MARKER:-Launching kybernet}"

# The slide window from src/main.cyr: 32 MB + slot * 2 MB, for slots 0..110.
LO=$((0x2000000))
HI=$((0xFE00000))
ALIGN=$((0x200000))

[ -n "$KERNEL" ] && [ -f "$KERNEL" ] || {
    echo "SKIP: set AGNOS_PIE_KERNEL to a PIE kernel, from tests/build_pie_agnos.sh"
    exit 77
}
# A fixed kernel would fail below with a misleading "no probe", so say why now.
e_type="$(od -An -tx1 -j16 -N2 "$KERNEL" | tr -d ' \n')"
[ "$e_type" = "0300" ] || { echo "FAIL: $KERNEL is not ET_DYN (e_type bytes $e_type)"; exit 1; }

D=$(mktemp -d -t gnoboot-kaslr.XXXXXX)
trap 'rm -rf "$D"' EXIT

FAILED=0

# Boot once and leave the kernel's base in $base, as hex with no prefix.
boot_once() {
    n="$1"
    printf '  boot %s expect "%s" ... ' "$n" "$MARKER"
    rc=0
    AGNOS_KERNEL="$KERNEL" EXPECT="$MARKER" SERIAL_LOG="$D/serial.$n" \
        QEMU_TIMEOUT="${QEMU_TIMEOUT:-60}" \
        "$ROOT/tests/ovmf_smoke.sh" >"$D/log.$n" 2>&1 || rc=$?
    if [ "$rc" -eq 77 ]; then
        echo "SKIP"
        sed -n '1p' "$D/log.$n"
        exit 77
    fi
    base="$(grep -a -o 'KASLR: kernel_base=[0-9a-fA-F]*' "$D/serial.$n" 2>/dev/null | head -1 | sed 's/.*=//')"
    if [ "$rc" -ne 0 ]; then
        echo "FAIL"
        sed -n '1,25p' "$D/log.$n" | sed 's/^/    /'
        FAILED=1
        return 0
    fi
    if [ -z "$base" ]; then
        echo "FAIL (reached the marker with no kernel_base probe)"
        FAILED=1
        return 0
    fi
    b=$((0x$base))
    if [ "$b" -lt "$LO" ] || [ "$b" -ge "$HI" ]; then
        echo "FAIL (0x$base is outside [32 MB, 254 MB): the slide fell back)"
        FAILED=1
    elif [ $((b % ALIGN)) -ne 0 ]; then
        echo "FAIL (0x$base is not 2 MB-aligned)"
        FAILED=1
    else
        echo "PASS (0x$base, $((b / 0x100000)) MB)"
    fi
}

echo "KASLR gate: $KERNEL"
boot_once 1
b1="$base"
boot_once 2
b2="$base"
[ "$FAILED" -eq 0 ] || { echo "KASLR gate: FAIL"; exit 1; }

# 111 slots tie about 1 boot pair in 111, so one tie is luck and not a stuck
# slide. A third boot settles it without a false failure.
if [ "$b1" = "$b2" ]; then
    boot_once 3
    [ "$FAILED" -eq 0 ] || { echo "KASLR gate: FAIL"; exit 1; }
    if [ "$base" = "$b1" ]; then
        echo "  FAIL: 0x$b1 on all three boots: the slide is stuck"
        echo "KASLR gate: FAIL"
        exit 1
    fi
fi

# A CPU without RDRAND must take the deterministic fallback, not fault. gnoboot
# ran `rdrand` unchecked until v0.9.0, which was #UD on such a CPU. The fixed
# base proves gnoboot got through and the kernel started; agnos needs RDRAND
# itself and stops soon after, so this does not wait for the marker.
printf '  no RDRAND expect base 0x2000000 ... '
rc=0
AGNOS_KERNEL="$KERNEL" EXPECT="KASLR: kernel_base=2000000" QEMU_CPU="max,rdrand=off" \
    QEMU_TIMEOUT=20 "$ROOT/tests/ovmf_smoke.sh" >"$D/log.nordrand" 2>&1 || rc=$?
if [ "$rc" -eq 77 ]; then
    echo "SKIP"
    exit 77
fi
if [ "$rc" -ne 0 ]; then
    echo "FAIL"
    sed -n '1,25p' "$D/log.nordrand" | sed 's/^/    /'
    echo "KASLR gate: FAIL"
    exit 1
fi
echo "PASS"

echo "KASLR gate: PASS"
