# Visicom palette evidence and future selection

This document keeps the Visicom COM-100 palette evidence, current comparison,
and future user-selection requirements together. None of the observed print or
capture values below is an accepted hardware-default palette.

## Colour indices

The core produces a two-bit Visicom colour index. The implemented lookup is:

| Index | Conventional name | Current RGB |
|---:|---|---:|
| `0` | dark green; also border/background | `#004000` |
| `1` | cyan | `#AFDFE4` |
| `2` | yellow | `#B9C42F` |
| `3` | red | `#EF454A` |

The names describe the current visible result; the two-bit index is the stable
machine-facing identity. Plane-index order and the border/background
relationship still require hardware review independently of palette fitting.

## Emulator palettes

The current core uses the same four values as MAME's Visicom driver. Emma 02
uses the same background green and brighter, more pastel foreground colours.

| Source | `0` | `1` | `2` | `3` |
|---|---:|---:|---:|---:|
| Current core / MAME | `#004000` | `#AFDFE4` | `#B9C42F` | `#EF454A` |
| Emma 02 | `#004000` | `#70D0FF` | `#D0FF70` | `#FF7070` |

Source locations:

- Current core: the `vis_rgb` lookup in `Studio-II.sv`.
- MAME: `VISICOM_PALETTE` in
  <https://github.com/mamedev/mame/blob/master/src/mame/rca/studio2.cpp>.
- Emma 02: the Visicom configuration in
  <https://github.com/etxmato/emma_02>.

## Local primary and print references

Original reference files stay local and immutable under `refs/Visicom video/`.
They are evidence, not build inputs. The print images have stable IDs and
SHA-256 hashes in `refs/Visicom video/palette-references/README.md`.

### FLiP hardware videos

- `visicom-bowling.mov`: H.264, 1280x720, 60 frames/s, approximately 75.4 s;
  colour metadata is absent.
- `visicom-race.mov`: H.264, 1280x720, 60 frames/s, approximately 21.1 s;
  video-range SMPTE 170M primaries/matrix with a BT.709 transfer tag.

The two captures are reasonably consistent with each other, but both include
the complete console, analog, display, camera, and encoding path.

### Flyer

- `VISC-PAL-FLYER-01`: crop of the arithmetic screen.
- `VISC-PAL-FLYER-02`: the same printed photograph at wider scale, retaining a
  person and room context for judging source-wide hue and saturation loss.

These are two views of one source and must not be counted as independent colour
observations.

### Visicom user manual

- `VISC-PAL-MANUAL-01`: repeating line patterns.
- `VISC-PAL-MANUAL-02`: small multicolour drawing.
- `VISC-PAL-MANUAL-03`: game screen with a red block and cyan targets.

These are separate printed screenshots. The manual edition and page numbers
remain unknown.

### Nicole Express source set

- `VISC-PAL-NICOLE-01`: complete Visicom COM-100 box/front marketing scene.
- `VISC-PAL-NICOLE-02`: clean close view of the television in that material.
- `VISC-PAL-NICOLE-03`: separate 7.033-second running-screen capture showing
  all three foreground colours.

The files were supplied on 2026-08-31 and attributed by the supplier to Nicole
Express. The clean screen image is the current user-preferred Visicom
*source-look* palette reference. The video is 640x480 H.264 at 30 frames/s,
video-range YUV 4:2:0 tagged BT.709; its scene is severely underexposed, so the
tags do not make its encoded levels display-referred measurements.

## Uncorrected observations

The following values are robust encoded-RGB medians from the supplied material.
They make the sources easy to compare and reproduce, but they are not estimates
of the Visicom's electrical or display-referred RGB output.

| Observed source | `0` | `1` | `2` | `3` |
|---|---:|---:|---:|---:|
| FLiP videos, combined | `#2B4624` | `#555E96` | `#838435` | `#943603` |
| FLiP Bowling | `#2C4624` | `#555E95` | `#838435` | `#953604` |
| FLiP Race | `#223E19` | `#505B9C` | `#869241` | `#8F3200` |
| Flyer print | `#4B7841` | `#99C8C8` | `#E7CA51` | `#D5A696` |
| User-manual print | `#70B331` | `#08B3C7` | `#F2D91D` | `#C03847` |
| Nicole Express clean screen, preferred source look | `#3C8E61` | `#6AC0D9` | `#FDFF8D` | `#F59AB2` |
| Nicole Express running video, severely underexposed | `#000F00` | `#08355B` | `#4E4C0B` | `#5E0609` |

The FLiP combined row samples 49 frames across the two videos. The print rows
sample clean screen regions. Family masks separate the four nominal colours,
then robust channel estimates reduce compression, halftone, dirt, and isolated
highlight influence. No matrix, transfer, black-level, gain, gamma, chroma
phase, gamut, paper, scanner, camera, or CRT correction has been applied.

The Nicole Express clean-screen row uses robust medians from the brighter,
more saturated core of each colour family. Its background estimate is stable
across the screen, and the reduced full-box image independently gives a nearly
identical green (`#3E8E63`). The full-box foreground characters are too small
for an equally reliable four-colour extraction. The video row samples 14 frames
at two frames/s; it preserves useful hue ordering but not useful absolute
levels.

The three manual screens vary most strongly in red:

| Manual image | Observed red |
|---|---:|
| Patterns | `#BF384B` |
| Drawing | `#BA2B43` |
| Game screen | `#C4391D` |

That magenta-red to orange-red spread is direct evidence that the print/scan
path can move hue enough to defeat a literal RGB match.

An earlier uncorrected YouTube Freeway sample recorded in the core was
`#003700`, `#B1ECE6`, `#DCE12D`, and `#FF3D46`. Its summed Euclidean RGB
distance was 86 to MAME and 225 to Emma 02. It supported choosing MAME as the
initial default, but it did not account for the capture path and is not a
hardware calibration.

## Comparison

- The raw observed medians lean toward MAME overall. Mean uncorrected Lab
  distances for FLiP, flyer, and manual were respectively 36.8, 27.4, and 30.5
  from MAME versus 39.1, 32.0, and 32.6 from Emma 02.
- Normalizing away much of each source's global brightness and saturation shift
  makes the palette geometry effectively a tie. The corresponding pairwise
  shape errors were 9.10, 11.74, and 6.55 for MAME versus 8.61, 7.96, and 6.46
  for Emma 02. These numbers are diagnostics, not confidence intervals.
- The manual's cyan hue is close to MAME's, while Emma 02 is visibly bluer. The
  manual cyan is nevertheless much more saturated than MAME's.
- The manual yellow is brighter and more saturated than MAME's. Emma 02 moves in
  that direction but is unusually bright and greenish.
- MAME's red is closer to the manual than Emma 02's pastel red. The manual
  generally suggests a darker, richer red, but the individual printed screens
  disagree about its exact hue.
- The flyer supports a MAME-like cyan hue and a stronger yellow, while its red
  is heavily attenuated by the publication/ageing path.
- The cleaner Nicole Express screen resolves the preferred printed look as a
  brighter teal-green field, saturated blue-cyan, pale lemon yellow, and pink
  red. It is not a small exposure change from the damaged flyer; every colour
  family is cleaner and the red is substantially less attenuated.
- The Nicole Express running video is too dark for level fitting, but its cyan
  is blue-cyan rather than FLiP's violet-blue and its red is near red rather
  than FLiP's orange-red. It independently reinforces the conclusion that the
  FLiP capture has a significant chroma-phase rotation.
- FLiP renders index 1 as violet-blue and index 3 as orange-red while lowering
  the whole palette. That coordinated hue rotation is consistent with an
  unresolved analog/capture matrix or chroma-phase effect; its encoded RGB
  values must not be copied into the core as hardware truth.
- Background green is especially sensitive to black level, display flare, and
  exposure. The agreement or disagreement of raw index-0 values is weak
  evidence for its native level.

The current conclusion is therefore narrow: MAME remains the better supported
provisional default, but none of the supplied material yet justifies replacing
it with a new hardware-derived table. The likely direction is MAME-like
foreground hues with stronger manual-like saturation, not a direct copy of
Emma 02 or any observed row above.

### Working source interpretation

The current visual judgment is that the flyer may be the most plausible guide
to the consumer Visicom's final analog/CRT appearance. The manual looks more
idealized: it may have been cleaned up for publication, or may resemble the
colour relationships before loss in the analog and display path. This is a
useful working hypothesis, not established provenance, so the flyer and manual
remain separately labelled sources.

The cleaner Nicole Express screen now supersedes the damaged flyer crop as the
preferred source *look*. Its working preset values are `#3C8E61`, `#6AC0D9`,
`#FDFF8D`, and `#F59AB2`. These values intentionally reproduce the supplied
image's appearance; they are not claimed as recovered electrical RGB or as the
future hardware-accuracy default.

### Expected 1978 flyer print path

The regular dot structure visible across the flyer is consistent with a
conventional screened four-colour reproduction, most likely offset lithography.
The scan alone cannot prove the press type, paper stock, screen ruling, ink set,
or whether the source photograph was a negative or transparency.

There was no national Japanese offset-colour standard comparable to modern
Japan Color in 1978. Japan Color's own history places its first representative
press tests in 1995, and an ICC history notes that Japan still had no such
standard in the 1990s. A Japanese printer in 1978 therefore likely worked to
house separations, proofs, solid-ink densities, and dot-gain aims. The first
widely accepted SWOP publication-print specification was assembled in the US
from 1974, but it is only a contemporary scale reference for this Japanese
flyer, not evidence of the flyer's production target.

Useful references:

- Japan Color history:
  <https://japancolor.jp/about/history.html> and
  <https://www.color.org/JapanColor2005English.pdf>.
- SWOP history:
  <https://idealliance.org/what-are-swop-and-gracol-and-how-do-they-relate-to-g7/>.
- Later SWOP Grade 5 characterization data:
  <https://registry.color.org/cmyk-registry/cgats_tr_005>.
- Archived ICC dot-gain guidance:
  <https://archive.color.org/files/faqs.pdf>.
- Kodak's description of photographic colour-reproduction errors:
  <https://www.kodak.com/content/products-brochures/Film/Exploring-the-Color-Image.pdf>.

A reasonable order-of-magnitude allowance for conventional screened offset is
roughly 15 to 25 percentage points of midtone tone-value increase: a nominal
50% dot may cover approximately 65% to 75% on paper. This is not a measured
1978 flyer value. For comparison, much later SWOP Grade 5 characterization
reports about 16% to 20% at 50% across CMYK, while archived ICC guidance gives
roughly 18% for positive-working and 25% for negative-working conditions. Dot
gain darkens midtones, compresses separation between nearby tones, and changes
hue whenever the separations gain unequally.

The likely colour tendencies are not symmetric:

- Yellow is the lightest process ink and commonly survives as the cleanest,
  brightest colour. Kodak gives example neutral densities of 0.16 for yellow,
  0.61 for cyan, and 0.76 for magenta. Yellow screen ruling and dot gain can
  nevertheless introduce an overall yellow cast.
- Cyan and magenta are darker inks. A light CRT cyan can lose saturation or
  become grayish when converted through film, separations, paper white, and a
  coarse halftone.
- Red requires magenta and yellow overprint. It moves orange when yellow wins
  and magenta when magenta wins; unequal gain or registration affects it more
  than a single-ink colour.
- Green requires cyan and yellow overprint and commonly becomes darker or more
  olive as cyan impurity, yellow bias, and dot gain accumulate.
- Blue requires cyan and magenta overprint, making it both dark and sensitive
  to a purple/blue balance error.

Kodak's general photographic-reproduction account is strikingly relevant to a
photographed CRT: blues, cyans, and greens tend to reproduce too dark; reds,
oranges, and yellows too light; saturation is lost; reds tend toward orange;
and cyans/greens tend toward blue. Those are tendencies of the photographic
colour materials, not a deterministic correction for this page.

The wider flyer view adds an important internal check. The child's yellow and
red clothing remains strongly saturated, so the press/scan path was capable of
carrying vivid yellow and red elsewhere on the same page. The weak, pale screen
red therefore cannot be blamed solely on a global inability of the inks to
print red. CRT exposure, phosphor bloom, the camera/film response, local colour
separation, and the actual Visicom signal remain plausible contributors.

Paper yellowing and scan white balance probably add a later warm bias, reducing
blue reflectance and making cyan/magenta relationships less trustworthy. With
no colour target or known paper white, the flyer should carry more weight for
colour ordering and broad hue relationships than for literal RGB, absolute
luminance, or saturation. It should not be “corrected” with one global phase,
gamma, or saturation value.

### FLiP chroma-phase test

An encoded YIQ test rotated the FLiP chroma vector while leaving luma and chroma
amplitude unchanged. Positive rotation moves FLiP's violet-blue toward cyan and
its orange-red toward red/magenta. The flyer comparison consistently prefers
that positive direction:

- the best shared foreground-chroma rotation is approximately `+16°`;
- including all four colours gives approximately `+15°`;
- Bowling alone gives approximately `+16°`, and Race approximately `+22°`.

At `+16°`, the unscaled FLiP medians become `#2F451D`, `#4D638E`, `#8D7D3C`,
and `#9D2A29`. This improves the yellow and red hue relationship, but the cyan
remains substantially too blue compared with the flyer.

Fitting each colour separately exposes the limit of a single phase correction:

| Index | `0` | `1` | `2` | `3` |
|---|---:|---:|---:|---:|
| Phase required to match flyer chroma direction | `-1°` | `+53°` | `+16°` | `+5°` |

Rotating far enough to align index 1 (`+53°`) turns index 2 brownish-red and
index 3 magenta. A global phase error is therefore present in the useful
direction, but cannot by itself transform FLiP into the flyer. The remaining
difference requires some combination of colour-dependent capture response,
chroma amplitude, transfer, print attenuation, and possibly source sampling
error. A future fit should start near `+15°` to `+20°`, then solve the other
transforms without allowing index 1 alone to dictate phase.

## Future selectable palettes

Palette selection is an output feature. It must consume the existing two-bit
index and must not change raster timing, DMA, plane state, memory, controls, or
machine reset behavior.

The intended Visicom design has three layers:

1. A named hardware-default preset, initially the current MAME table. Changing
   the accepted default after better evidence updates one palette definition,
   not the machine model.
2. Named alternatives, at minimum MAME/current, Emma 02, and the user-preferred
   Nicole Express source look. Any palette derived from a capture or printed
   source must be labelled as that source's *look*, never as hardware truth.
3. A user-supplied four-entry, 24-bit RGB palette that can be loaded without
   editing HDL or running Quartus. This is the immediate path for applying new
   measurements or personal preferences before a core release adopts them.

The eventual external format and MiSTer loading route remain implementation
decisions. Whatever route is selected must satisfy these requirements:

- define exactly four entries in index order `0` through `3`;
- accept arbitrary 24-bit RGB values;
- apply changes at the final indexed-colour lookup without a machine reset;
- fall back safely to the selected built-in preset when a file is missing,
  incomplete, or invalid;
- keep the accepted hardware default distinct from preference presets;
- use one lookup path for built-in and custom palettes rather than parallel
  video implementations;
- avoid title- or CRC-specific automatic colour selection;
- affect HDMI and direct-video colour consistently wherever both consume the
  same final RGB path.

The Nicole Express values above are the first explicitly preferred source-look
preset candidate. Raw flyer, manual, and FLiP observation rows may seed further
optional source-look presets, but they are not approved preset constants yet.
Freeze every such preset only with its provenance and transformation caveats
attached.

## Acceptance checks for the future implementation

- Exhaustively verify all four index-to-RGB mappings for every built-in preset.
- Verify valid and invalid custom-palette loads, fallback, reload, and index
  order.
- Prove palette changes do not reset or alter machine, raster, DMA, or plane
  state.
- Capture the same reviewed test pattern over HDMI and direct video.
- Keep the supported hardware-default decision gated on repeatable analysis and
  hardware review, independently of whether users can select alternatives.
