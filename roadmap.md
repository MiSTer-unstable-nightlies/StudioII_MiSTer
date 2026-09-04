# Roadmap

Only unfinished work belongs here. Accepted behavior belongs in the focused
technical documents; completed milestones belong in release notes and Git.

## Reference analysis

- Inventory original FLiP material with stable IDs, supplied descriptions,
  machine/capture metadata, sizes, and cryptographic hashes.
- Keep original `refs/` material local and immutable. Commit reusable analysis
  code and only the small derived measurements needed to support a decision.
- Build one repeatable video pipeline for colour clusters, geometry, sync, and
  temporal stability, with capture-path assumptions kept separate from source
  signal inferences.
## Fidelity work

### Visicom video

- Keep the evidence, current comparison, and future runtime-selection contract
  synchronized in `docs/visicom-palettes.md`.
- Derive a supported four-colour palette from stable regions across the supplied
  hardware captures, accounting for matrix, transfer, black level, gain, gamma,
  chroma phase, and compression uncertainty.
- Verify plane-index order, border/background relationship, active geometry, and
  placement independently of palette fitting.
- Accept the hardware-default palette only after automated index-to-RGB checks
  and hardware review. Keep optional user palette overrides separate from that
  default, and do not add automatic title-specific colours.

## Regression suite

- Document the headless harness contract: loading, reset settling, frame and input
  timing, capture outputs, machine selection, and reference-emulator limits.
- Replace uniform corpus scoring with a small declarative scenario manifest and
  one runner. Each case must identify its exact inputs, behavior under test,
  evidence, assertion class, and reviewed expected state.
- Use exact, property, human-review, or reference-comparison assertions according
  to what the evidence supports.
- Retain reviewable screenshots, diffs, timelines, hashes, and failure reasons.
- Prove each release-blocking test can fail through an appropriate negative
  control.
- Reuse useful driver code from the legacy scripts, but do not preserve their
  aggregate scores or unverified assumptions.

## Controller and keypad refinements

- Prevent the left analog stick from also generating ordinary profile movement
  while Numstick is using it to select `0`. Prefer automatic suppression while
  Numstick is active, unless an explicit left-stick option proves necessary.
- Verify the physical MPT-02-family joystick directions from primary material
  or hardware before describing them as equivalent to the neutral eight-way
  fallback. The matching Visicom layout is documented; similarity alone is not
  evidence for the MPT-02 family.

## Keyboard and keypad options

- Add optional physical numpad support, assigning the MiSTer keyboard's numeric
  keypad to console keypad A or B.
- Consider an Emma 02-style two-player layout: player one uses the keyboard
  number row and player two uses the physical numpad. Prefer independent A/B
  assignment for the number-row and numpad sources so either can drive either
  console keypad.
- Include the useful hybrid explicitly: retain the current logical keyboard
  layout on keypad A while the physical numpad drives keypad B.
- Add an optional conventional CHIP-8 QWERTY layout:

  | Original CHIP-8 keypad | Standard QWERTY mapping |
  |---|---|
  | `1` `2` `3` `C` | `1` `2` `3` `4` |
  | `4` `5` `6` `D` | `Q` `W` `E` `R` |
  | `7` `8` `9` `E` | `A` `S` `D` `F` |
  | `A` `0` `B` `F` | `Z` `X` `C` `V` |

- Add an optional literal CHIP-8 keyboard layout in which every COSMAC VIP
  keypad symbol uses its matching MiSTer keyboard key (`A` to `A`, `B` to `B`,
  and so on).
- Preserve the existing keyboard layout as the default. Implement these as
  selectable mappings into the existing A/B keypad masks, not as parallel
  machine-specific input paths.

## Selectable palettes

- Preserve hardware-accurate colours as the default while allowing the user to
  override the final indexed colours without changing machine behavior.
- Add two-entry, 1-bit palette support for Studio II foreground and background.
- Add four-entry, 2-bit palette support for Visicom. Its four indexed colours
  are a natural fit for Game Boy-style palette sets.
- Provide named Visicom presets, initially including the current/MAME, Emma 02,
  and preferred Nicole Express source-look tables, plus a user-loadable
  four-entry 24-bit RGB palette. Applying a custom palette must not require HDL
  edits, synthesis, or a machine reset.
- Label any optional flyer-, manual-, or capture-derived preset as a source
  *look*, not as the accepted hardware palette.
- Consider an optional expanded eight-entry palette for Studio III after the
  Studio II and Visicom paths are settled. Studio III already has a carefully
  matched hardware default, and its colour banding makes this a lower priority,
  but the eight-colour scope is still manageable.
- Keep palette selection an output customization only: it must not fork raster,
  DMA, colour-index, or machine state.

## Hardware and presentation

- Verify analog/direct-video timing and geometry on real hardware.
- Observe CHIP-8 sound-timer behavior separately on Studio II, Studio III PAL,
  and Studio III NTSC before changing audio routing.
- Create a small Studio III homebrew or demonstration that makes substantial use
  of the programmable tone generator, serving as both a musical showcase and a
  repeatable audio test program.
- Capture matching reviewed scenarios over HDMI and direct video.

## Deferred

High-page diagnostic ST2 images remain outside the 4 KB cartridge model. Do not
expand the loader without a concrete compatibility requirement and explicit
banking design.
