#!/usr/bin/env bash
echo "Retired: obsolete dump corpus. Use python3 tools/game-start-sweep.py with the approved Fullset ST2 folders." >&2
exit 1
# ---------------------------------------------------------------------------
# Directed test for the Toshiba Visicom COM-100 (--machine visicom).
#
#   tools/visicom-test.sh [--bios FILE]
#
# There is no reference emulator for this machine -- tools/refemu models the
# Studio II and the two Studio IIIs only, and Emma 02 has no headless mode -- so
# the reference frame diff cannot cover it. What this checks instead is the property
# that the whole implementation turns on: the Visicom's DMA reads *two* bytes,
# M(R(0)) and M(R(0)+$200), and combines their top bits into a 2-bit colour
# (Emma 02, Cdp1802::visicomDmaOut). Read one plane and you get a picture in one
# colour; read both and you get three foreground colours over the background.
#
# So this locks the exact set of colours each screen shows. Two of the four --
# yellow and salmon, indices 2 and 3 -- can only be produced when plane 1's bit
# is set, so any screen listing one of them is direct evidence the second read
# happened. The expected sets below were read off screens that were checked by
# eye against Emma's own descriptions of the games first (Addition really is a
# two-player scoreboard in two colours, Bagua really is a cyan border round the
# word HOROSCOPE), so this is a lock on verified output rather than on whatever
# the core happened to do.
#
# What it cannot prove on its own is that plane 1 sits at exactly +$200 rather
# than some other offset: a wrong offset would read program RAM and still light
# both planes. The evidence for the offset is that the pictures are clean --
# Addition's two score groups come out solidly cyan and solidly yellow, which a
# misaligned second plane would break up.
#
# The start keys are Emma 02's own (Helpfiles/FaqVisicomBuiltInGames.htm and
# FaqVisicomCartridges.htm): the built-ins are 1 Doodle, 2 Bowling, 3 Patterns,
# 4 Freeway, 7 Addition. Cartridge checks sample A0 only; they do not establish
# other mode selectors or complete cartridge startup coverage.
# ---------------------------------------------------------------------------
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="$ROOT/verilator/obj_dir_headless/Vtop"
BIOS="$ROOT/rom/visicom.rom"
CARTS="$ROOT/software/Visicom-Cartridges"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

while [[ ${1:-} == --* ]]; do
    case "$1" in
        --bios) BIOS="$2"; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 1 ;;
    esac
done
[[ -f "$ROOT/$BIOS" ]] && BIOS="$ROOT/$BIOS"

[[ -x "$RTL" ]]  || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }
[[ -f "$BIOS" ]] || { echo "error: no Visicom BIOS at $BIOS (pass --bios FILE)" >&2; exit 1; }

fail=0

# Prints the distinct colour letters in the captured frame, e.g. "CGY".
# G is the background (colour 0), C colour 1, Y colour 2, R colour 3.
colours() {   # $@ = extra sim args
    "$RTL" --machine visicom --bios "$BIOS" --frames 250 --shot 250 --ascii "$@" 2>/dev/null \
      | grep -E "^ *[0-9]+ \|" | sed 's/^ *[0-9]* |//; s/|$//' \
      | grep -o . | sort -u | tr -d '\n'
}

check() {   # $1 = label, $2 = expected colour set (sorted), rest = sim args
    local label="$1" want="$2"; shift 2
    local got
    got=$(colours "$@")
    if [[ "$got" == "$want" ]]; then
        printf "  ok    %-34s %s\n" "$label" "$got"
    else
        printf "  FAIL  %-34s got %s, expected %s\n" "$label" "$got" "$want"
        fail=1
    fi
}

echo "Visicom COM-100 built-in games:"
check "Doodle   (1)"  GR   --press a1@40:20
check "Bowling  (2)"  GY   --press a2@40:20
check "Patterns (3)"  GR   --press a3@40:20
check "Freeway  (4)"  CGRY --press a4@40:20
check "Addition (7)"  CGY  --press a7@40:20

echo "Visicom COM-100 cartridges (A0 colour samples only):"
CART_WANT=(
    "cas-110-arithmetic_drill        CGRY"
    "cas-130-sports_fan              CGRY"
    "cas-140-gambler_i               GY"
    "cas-141-gambler_ii              CGY"
    "cas-160-space_command           CGRY"
    "cas-190-bagua-blood-horoscope   CG"
)
seen=""
for e in "${CART_WANT[@]}"; do
    read -r n want <<<"$e"
    f="$CARTS/$n.st2"
    [[ -e "$f" ]] || { echo "  skip  $n (not in $CARTS)"; continue; }
    check "$n" "$want" --cart "$f" --press a0@40:20
    seen="$seen$want"
done

# The Visicom raw dumps are the same eight payload pages as their .st2 forms,
# without the 256-byte page-table header. One representative raw boot locks the
# machine-specific $0800 base; $0400 would overwrite firmware and leave the last
# four cartridge pages absent. Inspiration's headered CRC also has an explicit
# table entry, so start it through gamepad Start to lock its required A0 mapping.
inspiration="$CARTS/cas-190-bagua-blood-horoscope.st2"
if [[ -e "$inspiration" ]]; then
    raw="$TMP/cas-190-bagua-blood-horoscope.bin"
    tail -c +257 "$inspiration" > "$raw"
    check "Inspiration raw .bin" "CG" --cart "$raw" --joy 0x40@40:20
    check "Inspiration Start -> A0" "CG" --cart "$inspiration" --joy 0x40@40:20
else
    echo "  skip  raw loader and Start mapping (Inspiration not in $CARTS)"
fi

# Between them the cartridges must exercise all four colours. Y and R require
# plane 1's bit, so this is the check that the second DMA read happens at all.
missing=""
for c in C G R Y; do [[ "$seen" == *"$c"* ]] || missing="$missing$c"; done
if [[ -z "$missing" ]]; then
    echo "  ok    all four colours seen across the set"
else
    echo "  FAIL  colours never seen: $missing (plane 1 may not be read)"
    fail=1
fi

# The background must be colour 0, which is Emma's 0,64,0 -- a dark green, not
# black. Its 3-bit stand-in here is G, so a screen with nothing drawn is solid
# G. Anything else means the index is not landing on 0 off-bitmap.
echo "Background:"
blank=$("$RTL" --machine visicom --bios "$BIOS" --frames 20 --shot 20 --ascii 2>/dev/null \
        | grep -E "^ *[0-9]+ \|" | sed 's/^ *[0-9]* |//; s/|$//' | grep -o . | sort -u | tr -d '\n')
if [[ "$blank" == "G" ]]; then
    echo "  ok    before any key: solid background colour 0"
else
    echo "  FAIL  before any key: expected solid G, got '$blank'"
    fail=1
fi

exit $fail
