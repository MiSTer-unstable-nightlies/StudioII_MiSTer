#!/usr/bin/env bash
# Directed checks for boot-slot isolation and native CHIP-8 address routing.
# Uses an already-built headless Verilator model; it never starts a build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${HEADLESS_SIM:-$ROOT/verilator/obj_dir_headless/Vtop}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FW="$TMP/chip8.bin"

[[ -x "$SIM" ]] || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }

# Loader fixtures only: no interpreter execution or external software required.
# Distinct bytes at every boundary, plus one rejected byte at offset $900.
python3 - "$TMP/boundaries.ch8" "$FW" "$TMP/truncated.rom" <<'PY'
import sys
data = bytearray((i * 73 + 19) & 0xff for i in range(0x901))
for offset, value in ((0x000, 0x10), (0x4ff, 0x4f), (0x500, 0x50),
                      (0x8ff, 0x8f), (0x900, 0x90)):
    data[offset] = value
open(sys.argv[1], "wb").write(data)
firmware = bytes((i * 29 + 7) & 0xff for i in range(0x300))
open(sys.argv[2], "wb").write(firmware)
open(sys.argv[3], "wb").write(firmware[:0x2ff])
PY

run_case() {
    local machine=$1 bios=$2 fw=$3 source=${4:-auto}
    echo "CHIP-8 loader: $machine"
    if [[ -n "$fw" ]]; then
        if [[ "$source" == manual ]]; then
            "$SIM" --machine "$machine" --bios "$bios" --manual-chip8-fw "$fw" \
                --ch8 "$TMP/boundaries.ch8" --loader-check --quiet
        else
            "$SIM" --machine "$machine" --bios "$bios" --chip8-fw "$fw" \
                --ch8 "$TMP/boundaries.ch8" --loader-check --quiet
        fi
    else
        "$SIM" --machine "$machine" --bios "$bios" \
            --ch8 "$TMP/boundaries.ch8" --loader-check --quiet
    fi
}

run_case studio2     "$ROOT/rom/studio2.rom"      "$FW" || exit 1
run_case mpt02       "$ROOT/rom/studio3_pal.bin" "$FW" || exit 1
run_case studio3ntsc "$ROOT/rom/studio3_ntsc.bin" "$FW" || exit 1
run_case visicom     "$ROOT/rom/visicom.rom"      "$FW" || exit 1

echo "CHIP-8 loader: manual interpreter cache"
run_case studio2 "$ROOT/rom/studio2.rom" "$FW" manual || exit 1

echo "CHIP-8 loader: bundled OpenStudio2 without an override"
run_case studio2     "$ROOT/rom/studio2.rom"     "" || exit 1
run_case mpt02       "$ROOT/rom/studio3_pal.bin" "" || exit 1
run_case studio3ntsc "$ROOT/rom/studio3_ntsc.bin" "" || exit 1
run_case visicom     "$ROOT/rom/visicom.rom"     "" || exit 1

echo "CHIP-8 loader: truncated interpreter override"
run_case studio2 "$ROOT/rom/studio2.rom" "$TMP/truncated.rom" manual || exit 1

echo "CHIP-8 loader checks passed"
