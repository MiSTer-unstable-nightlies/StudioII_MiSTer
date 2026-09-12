#!/usr/bin/env bash
# Directed Visicom cartridge-ownership regression. Uses an already-built
# headless Verilator model; it never starts a build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${HEADLESS_SIM:-$ROOT/verilator/obj_dir_headless/Vtop}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[[ -x "$SIM" ]] || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }

# The full cartridges seed all eight Visicom cartridge pages. The partial
# replacements supply only $08-$0B, leaving stale bytes physically present in
# $0C-$0F. The ST2 case also tries to target resident page $04; it must be
# rejected so the complete $0000-$07FF firmware remains intact.
python3 - "$TMP" <<'PY'
import pathlib
import sys

out = pathlib.Path(sys.argv[1])

def pages(values):
    return b''.join(bytes([value]) * 0x100 for value in values)

def st2(path, target_pages, values):
    header = bytearray(0x100)
    header[:4] = b'RCA2'
    for block, page in enumerate(target_pages):
        header[0x40 + block] = page
    path.write_bytes(header + pages(values))

(out / 'resident.rom').write_bytes(pages(range(0x10, 0x18)))
(out / 'full.bin').write_bytes(pages(range(0x20, 0x28)))
(out / 'partial.bin').write_bytes(pages(range(0x40, 0x44)))
st2(out / 'full.st2', range(0x08, 0x10), range(0x20, 0x28))
st2(out / 'partial.st2', [0x04, 0x08, 0x09, 0x0a, 0x0b],
    [0xee, 0x40, 0x41, 0x42, 0x43])
PY

run_case() {
    local kind=$1 full=$2 partial=$3
    echo "Visicom loader: $kind full -> partial"
    "$SIM" --machine visicom --bios "$TMP/resident.rom" --cart "$full" \
        --swap "$partial@1" --frames 3 --loader-check --quiet
}

run_case raw "$TMP/full.bin" "$TMP/partial.bin"
run_case ST2 "$TMP/full.st2" "$TMP/partial.st2"

echo "Visicom loader checks passed"
