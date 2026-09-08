#!/usr/bin/env bash
echo "Retired: obsolete dump corpus. Use python3 tools/game-start-sweep.py with the approved Fullset ST2 folders." >&2
exit 1
# ---------------------------------------------------------------------------
# The Studio III / Conic PAL score: every Conic cartridge, started with A1, and
# diffed RTL against tools/refemu.
#
#   tools/score-conic.sh [--machine mpt02|studio3ntsc] [--bios FILE]
#
# This reproduces the historical uniform-A1 sweep. Its raw total is diagnostic,
# not an accuracy percentage; only manifest cases expected to match belong in an
# acceptance score (see AGENTS.md, change discipline).
# ---------------------------------------------------------------------------
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CG="$ROOT/tools/compare-game.sh"
REF="$ROOT/tools/refemu/studio2_headless"
[[ -x "$REF" ]] || REF="$ROOT/refs/rca-studio2/studio2-games/studio2/studio2_headless"
RTL="$ROOT/verilator/obj_dir_headless/Vtop"

MACHINE=mpt02
BIOS="$ROOT/rom/studio3_pal.bin"
while [[ ${1:-} == --* ]]; do
    case "$1" in
        --machine) MACHINE="$2"; shift 2 ;;
        --bios)    BIOS="$2";    shift 2 ;;
        *) echo "unknown option $1" >&2; exit 1 ;;
    esac
done
[[ -f "$BIOS" ]] || { echo "error: no BIOS at $BIOS" >&2; exit 1; }
[[ -x "$REF" ]] || { echo "error: build the reference: (cd tools/refemu && make headless)" >&2; exit 1; }
[[ -x "$RTL" ]] || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }

pass=0; tot=0; errors=0
for d in Conic_StudioIII-Cartridges Conic_StudioIII-Homebrew Conic_StudioIII-Sarnoff-Collection; do
    dir="$ROOT/software/$d"
    [[ -d "$dir" ]] || continue
    echo "$d:"
    for f in "$dir"/*.st2; do
        [[ -e "$f" ]] || continue
        raw=$("$CG" --machine "$MACHINE" --bios "$BIOS" "$f" 300 150,300 --press a1@40:20 2>&1)
        out=$(printf '%s\n' "$raw" | grep -E "frame +[0-9]+ +(MATCH|DIFFER)" || true)
        if [[ -z "$out" ]]; then
            printf "  ERROR %-52s comparison produced no frame results\n" "$(basename "$f" .st2)" >&2
            printf '%s\n' "$raw" | sed 's/^/        /' >&2
            errors=$((errors+1))
            continue
        fi
        n=$(printf '%s' "$out" | grep -c MATCH)
        t=$(printf '%s' "$out" | grep -c .)
        pass=$((pass+n)); tot=$((tot+t))
        printf "  %-52s %s/%s\n" "$(basename "$f" .st2)" "$n" "$t"
    done
done
echo
echo "  frames matching: $pass / $tot   (machine $MACHINE)"
[[ $errors -eq 0 ]] || { echo "  comparison errors: $errors" >&2; exit 2; }
