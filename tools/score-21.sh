#!/usr/bin/env bash
echo "Retired: obsolete dump corpus. Use python3 tools/game-start-sweep.py with the approved Fullset ST2 folders." >&2
exit 1
# ---------------------------------------------------------------------------
# Every Studio II case, driven with its *documented* start
# sequence (from the RCA manuals, same sequences as tools/play-test.sh), and
# diffed RTL against the reference emulator.
#
#   tools/score-21.sh
#
# The original figure was measured
# by hand, which made it awkward to tell whether a change had moved it. Using a
# uniform "press A1" instead is not the same metric: several cartridges never
# start, so their frames agree only because both sides show the same near-empty
# screen.
# ---------------------------------------------------------------------------
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CG="$ROOT/tools/compare-game.sh"
S2="$ROOT/software/StudioII-Cartridges"
S3="$ROOT/software/Conic_StudioIII-Cartridges"
REF="$ROOT/tools/refemu/studio2_headless"
[[ -x "$REF" ]] || REF="$ROOT/refs/rca-studio2/studio2-games/studio2/studio2_headless"
RTL="$ROOT/verilator/obj_dir_headless/Vtop"

[[ -x "$REF" ]] || { echo "error: build the reference: (cd tools/refemu && make headless)" >&2; exit 1; }
[[ -x "$RTL" ]] || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }

pass=0; fail=0; errors=0
score() {   # $1=label  $2=cart-or-"-"  $3=frames  $4=shots  rest=presses
    local label="$1" cart="$2" frames="$3" shots="$4"; shift 4
    local raw out n tot
    if [[ "$cart" != "-" && ! -f "$cart" ]]; then
        printf "  ERROR %-44s cartridge not found: %s\n" "$label" "$cart" >&2
        errors=$((errors+1))
        return
    fi
    raw=$("$CG" "$cart" "$frames" "$shots" "$@" 2>&1)
    out=$(printf '%s\n' "$raw" | grep -E "frame +[0-9]+ +(MATCH|DIFFER)" || true)
    if [[ -z "$out" ]]; then
        printf "  ERROR %-44s comparison produced no frame results\n" "$label" >&2
        printf '%s\n' "$raw" | sed 's/^/        /' >&2
        errors=$((errors+1))
        return
    fi
    n=$(printf '%s' "$out" | grep -c MATCH)
    tot=$(printf '%s' "$out" | grep -c .)
    pass=$((pass+n)); fail=$((fail+tot-n))
    printf "  %-44s %s/%s\n" "$label" "$n" "$tot"
}

echo "Built-in games (no cartridge):"
score "Doodle   (A1)"   - 300 150,300 --press a1@40:20
score "Patterns (A2)"   - 300 150,300 --press a2@40:20
score "Bowling  (A3)"   - 300 150,300 --press a3@40:20
score "Freeway  (A4)"   - 300 150,300 --press a4@40:20
score "Addition (A5)"   - 300 150,300 --press a5@40:20

echo "Cartridges, documented start sequences:"
score "Space War (A1, fire A2)"      "$S2/spacewar.st2"             300 150,300 --press a1@40:20 --press a2@150:20
score "Tennis (A2, size, speed)"     "$S2/tennis.st2"               300 150,300 --press a2@40:15 --press a5@90:15 --press b5@140:15
score "Squash (A1, size, speed)"     "$S2/tennis.st2"               300 150,300 --press a1@40:15 --press b5@90:15
score "Speedway (A1)"                "$S2/speedway.st2"             300 150,300 --press a1@40:20 --press a2@150:60
score "Tag (A2)"                     "$S2/speedway.st2"             300 150,300 --press a2@40:20 --press a6@150:60
score "Gunfighter (A1, fire 5)"      "$S2/gunfighter.st2"           300 150,300 --press a1@40:20 --press a5@150:20
score "Moonship (A3, fire 5)"        "$S2/gunfighter.st2"           300 150,300 --press a3@40:20 --press a5@150:20
score "Baseball (A0, pitch B5)"      "$S2/baseball.st2"             300 150,300 --press a0@40:20 --press b5@150:20
score "Blackjack (A1, bet B5)"       "$S2/blackjack.st2"            300 150,300 --press a1@40:20 --press b5@150:20
score "Star Wars (A1, speed A2)"     "$S3/star-wars.st2"            300 150,300 --press a1@40:20 --press a2@120:20
score "Fun with Numbers (A1)"        "$S2/fun-with-numbers.st2"     300 150,300 --press a1@40:20 --press b1@150:15 --press b2@180:15
score "Biorhythm (A0, dates on B)"   "$S2/biorhythm.st2"            300 150,300 --press a0@40:20 --press b1@120:15 --press b2@150:15
score "Pinball (A1)"                 "$S3/pinball.st2"               300 150,300 --press a1@40:20
score "Speedway+Tag Europe (A1)"     "$S3/speedway.st2"             300 150,300 --press a1@40:20 --press a2@150:60
score "School House I (A1)"          "$S2/school.st2"                300 150,300 --press a1@40:20
score "Math Fun (A1)"                "$S2/mathfun.st2"               300 150,300 --press a1@40:20
score "TV Bingo (A1)"                "$S3/bingo.st2"                 300 150,300 --press a1@40:20
score "Concentration Match (A1)"     "$S3/concentration-match.st2"   300 150,300 --press a1@40:20
score "Demonstration (A1)"           "$S2/RCA_demo.st2"              300 150,300 --press a1@40:20

# 86677b and 87201 are deliberately excluded: the reference emulator renders
# full-screen noise for both from the first frame, before any input, so neither
# side is a reference for the other (see AGENTS.md, change discipline).

echo
echo "  frames matching: $pass / $((pass+fail))"
[[ $errors -eq 0 ]] || { echo "  comparison errors: $errors" >&2; exit 2; }
