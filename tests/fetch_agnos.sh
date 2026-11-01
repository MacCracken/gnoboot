#!/bin/sh
# tests/fetch_agnos.sh — download the pinned agnos kernel for the boot gates.
#
# A runner has no agnos checkout, and ovmf_smoke.sh's 4-byte stub fails before
# the handoff banner prints, so the boot gates need a real ELF64 to do anything
# at all. The version lives in tests/AGNOS_VERSION, so a kernel release cannot
# move gnoboot's CI unannounced.
#
# Progress goes to stderr; stdout is only the verified kernel's path, so a
# caller can capture it.
#
# Usage:
#   tests/fetch_agnos.sh                 # into build/agnos-<version>/
#   tests/fetch_agnos.sh /path/to/dir

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(tr -d '[:space:]' < "$ROOT/tests/AGNOS_VERSION")"
DEST="${1:-$ROOT/build/agnos-$VER}"
BASE="https://github.com/MacCracken/agnos/releases/download/$VER"

mkdir -p "$DEST"
cd "$DEST"

for f in agnos-x86_64 SHA256SUMS; do
    curl -fsSL --retry 5 --retry-all-errors -o "$f" "$BASE/$f"
done
# --ignore-missing because SHA256SUMS also lists the source tarball. It still
# fails if no listed file was checked, so a renamed asset cannot pass silently.
sha256sum --check --ignore-missing SHA256SUMS >&2

echo "$DEST/agnos-x86_64"
