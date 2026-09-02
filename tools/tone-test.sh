#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Directed test for the Studio III programmable tone generator
# (rtl/pixie/cdp1863.v).
#
#   tools/tone-test.sh
#
# No cartridge in the corpus exercises the tone generator in a way the frame
# comparison can see -- frames carry no audio -- so this drives it directly with
# a hand-assembled native-1802 cartridge, one run per latch value, and measures
# the frequency from the sim's audio edge count.
#
# Expected from the sources (docs/development.md and the datasheets distilled
# in rtl/pixie/cdp1863.v):
#
#   f = clk / 8 / 4 / (latch+1) / 2      MAME's division chain
#   f = clk / 8     / (latch+1) / 2      native CDP1863 division chain
#
#   latch 255 ->   106.8 Hz   datasheet says the range bottoms out at 107 Hz
#   latch  53 ->   506.4 Hz   MAME's power-on default (0x35)
#   latch   1 -> 13671.9 Hz   datasheet says the range tops out at 13672 Hz
#
# Weisbecker's own Studio III notes say "64 instruction sets sound frequency
# (INVERSE)" and "Q gates sound output", so a larger latch must give a *lower*
# frequency, and nothing should come out at all while Q is low. Both checked.
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="$ROOT/verilator/obj_dir_headless/Vtop"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[[ -x "$RTL" ]]   || { echo "error: build the RTL sim: (cd verilator && make headless)" >&2; exit 1; }
# No machine BIOS is needed: the test program *is* the firmware.

# The core's pixel clock, which is also the CPU clock: clk_sys/4.
CLK=1760229
FRAMES=120

# Hand-assembled, same approach as tools/memdecode-test.sh: set the tone latch
# with OUT 4, raise Q, then spin. R2 is the OUT pointer (OUT takes its byte
# through M(R(X))).
# Run the test program AS the firmware rather than as a cartridge. Loading it at
# $0000 means it executes from reset with no BIOS in the way: no start-up beep to
# talk over, no interrupt handler stealing Q, and no display enabled (INP 1 is
# never issued), so the only thing driving AUDIO OUT is this program. That makes
# the measurement a clean read of the tone generator instead of a fight with the
# machine around it.
build() {   # $1 = latch byte, $2 = output path, $3 = 1 to raise Q
    python3 - "$1" "$2" "$3" <<'EOF'
import sys
latch, path, withq = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
#  At reset P=0 and X=0, so R0 is the PC. R2 becomes the OUT pointer, since OUT
#  takes its byte through M(R(X)).
code  = [0xF8, 0x08, 0xB2]                 # LDI $08 / PHI R2
code += [0xF8, 0x50, 0xA2]                 # LDI $50 / PLO R2   -> R2 = $0850
code += [0xF8, latch, 0x52]                # LDI latch / STR R2 -> M(R2) = latch
code += [0xE2]                             # SEX 2
code += [0x64]                             # OUT 4  -> load the tone divider
if withq:
    code += [0x7B]                         # SEQ    -> Q high = AOE = tone on
here = len(code)
code += [0x30, here & 0xFF]                # BR self
open(path, 'wb').write(bytes(code) + bytes(0x800 - len(code)))
EOF
}

# With no BIOS there is only ever one Q window, so no need to skip a start-up
# beep -- but keep taking the last one, which is also the only one.
measure() {  # $1 = firmware image, $2 = machine, remaining args = sim options
    local firmware="$1" machine="$2"
    shift 2
    "$RTL" --machine "$machine" --bios "$firmware" "$@" \
      --frames "$FRAMES" --trace-q --quiet 2>/dev/null \
      | awk -v tot="$FRAMES" '
          function cnt(x) { gsub(/[()]/,"",x); return x+0 }
          /^Q 1 frame/ { on=$4+0; e0=cnt($9); seen=1; closed=0 }
          /^Q 0 frame/ { if (seen) { de=cnt($9)-e0; df=$4+0-on; closed=1 } }
          /^audio:/    { if (seen && !closed) { de=$2-e0; df=tot-on } }
          END          { if (seen) print de, df; else print 0, 0 }'
}

fail=0
check() {   # $1 = latch
    local latch="$1" edges nframes hz want dev
    build "$latch" "$TMP/t.bin" 1
    read -r edges nframes <<<"$(measure "$TMP/t.bin" mpt02)"
    # frames -> seconds, edges -> half-cycles, so Hz = edges / 2 / seconds
    read -r hz want dev <<<"$(python3 - "$edges" "$latch" "$nframes" "$CLK" <<'EOF'
import sys
edges, latch, frames, clk = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
secs = frames * (112*312) / clk            # PAL frame = 112 px * 312 lines
hz   = (edges / 2) / secs if secs else 0
want = clk / 8 / 4 / (latch+1) / 2
print(f"{hz:.1f} {want:.1f} {abs(hz-want)/want*100 if want else 0:.1f}")
EOF
)"
    if (( $(python3 -c "print(1 if $dev < 2.0 else 0)") )); then
        printf "  ok    latch %3d (0x%02X)  %8s Hz   (expected %s, %s%% off)\n" "$latch" "$latch" "$hz" "$want" "$dev"
    else
        printf "  FAIL  latch %3d (0x%02X)  %8s Hz   (expected %s, %s%% off)\n" "$latch" "$latch" "$hz" "$want" "$dev"
        fail=1
    fi
}

echo "CDP1864 tone generator:"
for l in 1 15 53 127 255; do check "$l"; done

# The standalone CDP1863 on the NTSC Studio III omits the CDP1864's
# divide-by-four stage. Original NTSC pitch must therefore be exactly four
# times PAL for the same latch, while the OSD's lower setting selects that
# existing stage and must match PAL.
build 53 "$TMP/ratio.bin" 1
read -r pal_edges pal_frames <<<"$(measure "$TMP/ratio.bin" mpt02)"
read -r ntsc_edges ntsc_frames <<<"$(measure "$TMP/ratio.bin" studio3ntsc --ntsc-tone-pitch original)"
read -r low_edges low_frames <<<"$(measure "$TMP/ratio.bin" studio3ntsc --ntsc-tone-pitch pal)"
read -r pal_hz ntsc_hz low_hz native_ratio low_ratio native_ok low_ok <<<"$(
python3 - "$pal_edges" "$pal_frames" "$ntsc_edges" "$ntsc_frames" \
          "$low_edges" "$low_frames" "$CLK" <<'EOF'
import sys
pe, pf, ne, nf, le, lf, clk = map(int, sys.argv[1:])
def hz(edges, frames, lines):
    return (edges / 2) / (frames * 112 * lines / clk) if frames else 0
p = hz(pe, pf, 312)
n = hz(ne, nf, 262)
l = hz(le, lf, 262)
nr = n / p if p else 0
lr = l / p if p else 0
print(f"{p:.1f} {n:.1f} {l:.1f} {nr:.3f} {lr:.3f} "
      f"{int(abs(nr-4.0)/4.0 < 0.02)} {int(abs(lr-1.0) < 0.02)}")
EOF
)"

echo "Studio III pitch selection (latch 53):"
if [[ "$native_ok" == "1" ]]; then
    printf "  ok    native NTSC %s Hz is %sx PAL %s Hz\n" "$ntsc_hz" "$native_ratio" "$pal_hz"
else
    printf "  FAIL  native NTSC %s Hz is %sx PAL %s Hz, expected 4x\n" "$ntsc_hz" "$native_ratio" "$pal_hz"
    fail=1
fi
if [[ "$low_ok" == "1" ]]; then
    printf "  ok    lowered NTSC %s Hz matches PAL (%sx)\n" "$low_hz" "$low_ratio"
else
    printf "  FAIL  lowered NTSC %s Hz is %sx PAL %s Hz, expected 1x\n" "$low_hz" "$low_ratio" "$pal_hz"
    fail=1
fi

# Q low must silence it outright -- AOE holds AUDIO OUT low (datasheet p5).
build 53 "$TMP/q.bin" 0
read -r edges _ <<<"$(measure "$TMP/q.bin" mpt02)"
if [[ "$edges" == "0" ]]; then
    echo "  ok    Q low: silent (0 edges)"
else
    echo "  FAIL  Q low: expected 0 edges, got $edges"
    fail=1
fi

# And the Studio II must be untouched: it keeps its discrete 555 and ignores
# OUT 4 entirely. Testing that by absolute frequency would be wrong, because the
# default Medium model deliberately droops from about 625 Hz toward 502.5 Hz.
# Over a window this long the average lands nearer the sustained end. Test the
# property that matters here instead: two very different latch values must give
# the *same* frequency, because neither reaches the beeper.
build 1   "$TMP/s2a.bin" 1
build 255 "$TMP/s2b.bin" 1
read -r a af <<<"$(measure "$TMP/s2a.bin" studio2)"
read -r b bf <<<"$(measure "$TMP/s2b.bin" studio2)"
ahz=$(python3 -c "f=$af; print(round(($a/2)/(f*(112*262)/$CLK),1) if f else 0)")
bhz=$(python3 -c "f=$bf; print(round(($b/2)/(f*(112*262)/$CLK),1) if f else 0)")
same=$(python3 -c "
a,b=$ahz,$bhz
print(1 if a>0 and b>0 and abs(a-b)/max(a,b) < 0.02 else 0)")
if [[ "$same" == "1" ]]; then
    printf "  ok    Studio II ignores OUT 4: %s Hz and %s Hz for latch 1 vs 255\n" "$ahz" "$bhz"
    echo   "        (its Medium 555 tuning droops from ~625 to ~502.5 Hz, so the average depends"
    echo   "         on the window; what matters is that the latch cannot change it)"
else
    printf "  FAIL  Studio II frequency moved with the tone latch: %s Hz vs %s Hz\n" "$ahz" "$bhz"
    fail=1
fi

exit $fail
