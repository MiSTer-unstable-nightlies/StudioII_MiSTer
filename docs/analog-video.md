# Analog video verification

Status as of 2026-09-11: the current RTL generates a full raster with the bitmap
inside it. The implementation below was checked against the current source.
Verification is only partial; direct video is yet untested.

## Current raster

Timing is defined in `rtl/pixie/cdp1861.v` and `rtl/pixie/cdp1864.v`.
Studio II, Studio III NTSC, and Visicom use the CDP1861 timing path; Studio III
PAL uses CDP1864. All ranges below include the start and exclude the end, and
horizontal positions are native pixel times before top-level repetition.

| Property | CDP1861 timing | CDP1864 timing |
|---|---:|---:|
| Line length | 112 pixel times | 112 pixel times |
| Frame length | 262 lines | 312 lines |
| Front porch | `0..8` | `0..8` |
| HSync | `8..16` | `8..16` |
| Back porch | `16..24` | `16..24` |
| Active horizontal window | `24..112` | `24..112` |
| VSync | `254..258` | `0..4` |
| VBlank | `254..262` and `0..12` | `0..20` |
| Bitmap window | `40..104`, lines `80..208` | `40..104`, lines `76..268` |
| Active raster | 88 x 242 | 88 x 292 |
| Bitmap capture | 64 x 128 | 64 x 192 |
| Approximate line rate | 15.715 kHz | 15.715 kHz |
| Approximate frame rate | 59.98 Hz | 50.37 Hz |

`rtl/pll/pll_0002.v` specifies `clk_sys` at 7.040229 MHz. The native pixel
clock enable divides this by four, giving approximately 1.760057 MHz, or
568.16 ns per pixel time. A line is approximately 63.63 microseconds; each
8-pixel porch/sync interval is 4.55 microseconds, and active video lasts
50.00 microseconds. These are calculations from the configured clock, not
measurements. The 1.760229 MHz figure in a top-level comment is inconsistent
with the PLL's divide-by-four value.

The generators emit one bit per native pixel time. Firmware can repeat bitmap
rows through DMA/R0 addressing; the video generator does not itself expand
32 rows into 128 or 192 lines. The MiSTer integration subsequently repeats each
native pixel four times horizontally without changing line or frame duration.

With Borders On, the area around the bitmap is active background video:

- Studio II uses the selected palette background, black by default.
- Studio III NTSC and PAL use the selected background once display and colour
  are enabled; before that, the border is black. The background steps through
  blue, black, green, and red. The top level uses `0x80` for asserted background
  RGB channels and `0xFF` for foreground channels.
- Visicom uses palette colour 0, initially `#11320C` (dark green). Loading a
  palette can change it.

## Timing limitations

The horizontal bitmap window remains offset: 16 native pixels of border on the
left and eight on the right. Its fixed read window accommodates DMA arrival
phase; it is not a measurement of original hardware placement. Preserve the
DMA/interrupt/EF phase when investigating centring. See
[development.md](development.md) before changing timing.

The RTL comments reference CDP1864 datasheet Figures 4 and 6, but the current
porches are equal and do not reproduce the cited asymmetric hardware timing.
The PAL source also records conflicting vertical-blanking figures (20H versus
24H) and uses 20 lines. Its 192-line bitmap starts at line 76 following Emma 02;
the source explicitly calls for hardware checking before moving it. These
choices do not establish exact datasheet or hardware agreement.

Both generators produce a simple four-line VSync pulse. Display lock and the
resulting framework composite-sync waveform still need physical verification.

## MiSTer output path

`Studio-II.sv` currently uses:

```text
Native machine: clk_sys approximately 7.040229 MHz, ce_pix = clk_sys / 4
CLK_VIDEO = clk_vid approximately 42.241379 MHz
video_mixer input enable = clk_vid / 6, approximately 7.040230 MHz
CE_PIXEL = video_mixer output enable
video_mixer: LINE_LENGTH=352, GAMMA=1, hq2x=0
scandoubler = forced_scandoubler
VGA_SCALER = 0
VGA_SL = 0
VGA_DISABLE = 0
```

RGB passes through palette selection and the optional on-screen keypad, then
is sampled with sync and selected blanking into `clk_vid`. `video_mixer`
produces VGA RGB/HS/VS and derives DE from blanking. `video_freak` receives that
DE and supplies cropped DE and aspect/integer-scaling parameters to the MiSTer
framework; it does not scale the RGB stream itself. Only its VS input is delayed
by one `CE_PIXEL`, to preserve its active-line measurement. Output VGA VS is not
delayed by that adjustment.

The repeated full active line is 352 samples wide (88 x 4); with Borders Off,
it is 256 samples (64 x 4). `LINE_LENGTH=352` accommodates the full raster.
`VGA_SCALER=0` does not force the analog output through the HDMI scaler.

| Output | Configuration to test |
|---|---|
| Native 15 kHz display | Suitable analog IO connection, `forced_scandoubler=0` |
| VGA display supporting the resulting doubled timing | `forced_scandoubler=1`, approximately 31.43 kHz horizontal |
| Normal HDMI | Framework scaler path |
| Direct Video | `direct_video=1`, compatible external converter/display |

Borders Off selects bitmap HBlank/VBlank before the mixer. It changes the
presented active area without changing device HS, VS, or line/frame totals.
The optional 216-line crop is enabled only when the framework reports 1920x1080
and forced scandoubling is off. Direct Video reports zero scaler dimensions,
so crop is disabled there. Crop changes DE, not sync; check its effect on a
simultaneous analog output as well as HDMI.

## Reset behaviour

Machine reset and video reset are separate. CLEAR, recognised cartridge,
firmware and CHIP-8 downloads, and same-standard Apply and reset leave raster
timing running. Core/MiSTer reset, unknown downloads, and PAL/NTSC changes use a
hard video reset. A standard change can therefore require display resync.
Missing firmware or a blank game picture should not be treated as proof that
raster timing has stopped.

## Hardware verification

No physical analog result is recorded here. The following is a test procedure,
not a report of successful output:

1. Use a current build produced with the supported Quartus 17.0.x toolchain.
   Record the source revision and build used.
2. Start with a suitable native 15 kHz analog connection, forced scandoubling
   off, Borders On, crop off, and the on-screen keypad off.
3. Test Studio II, Studio III NTSC, Studio III PAL, and Visicom. Record sync
   stability, bitmap placement, visible border, and palette/background behaviour.
4. Toggle Borders. Confirm the active area changes while sync remains stable.
5. Exercise CLEAR, firmware/cartridge/CHIP-8 loads where supported, and
   same-standard Apply. Check that sync is retained. Separately test PAL/NTSC
   switching and record resync behaviour.
6. Repeat with forced scandoubling on a compatible VGA display, then with
   Direct Video and a compatible converter. Test the 1080p crop separately,
   including any simultaneous analog output.

For failure diagnosis, first establish the display's supported timing, cable,
converter, and relevant `MiSTer.ini` settings. For sync problems, record or
measure HS/VS and the configured composite-sync output before changing the
core. For horizontal displacement, compare against the implemented 16/8 border
split. For unexpected colours, check the active machine, loaded palette, and
software colour-enable state.

## Automated coverage and recording results

The headless harness captures `bitmap_de`, not the surrounding active raster,
and instantiates `rcastudioii` rather than `Studio-II.sv`. Bitmap captures do
not verify top-level resampling, mixer/scandoubler operation, crop, analog
levels, or physical display lock. Simulation can inspect raster signals with
directed checks; it is incorrect to say the raster cannot be tested at all.

Capture separation also does not make arbitrary timing changes harmless:
DMA, interrupt/EF timing, frame boundaries, and software execution can change
captured results. Any timing change needs directed checks of the affected
signals and relevant bitmap/gameplay regressions. Use the `--ce4` harness mode
for reset and CPU/DMA phase work. Simulation success does not replace an FPGA
build or physical analog verification.

This documentation update was checked against source only; no synthesis,
Verilator build, regression run, or display test was performed.

After hardware testing, record the build/revision, machine and firmware,
display/converter and connection, relevant `MiSTer.ini` and OSD settings, sync
stability, bitmap placement, border behaviour, and reset results here. Update
the video summary in [development.md](development.md) when those results change
its stated behaviour or verification status.
