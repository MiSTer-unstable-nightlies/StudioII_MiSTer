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

### Studio III NTSC display control

- Replay resident and Grand Pack Bowling through both players and multiple
  frames after the `OUT 1` decode correction; test Blackjack A4/A5 from CLEAR.
- Compare exact firmware bytes, display enable, PC, and DMA around any remaining
  blackout before attributing it to firmware or changing timing. Record the
  user's suspected A0 case separately; its behavior remains unconfirmed.

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

### Near-term automapping cleanup

Every game's profile must answer: **is this mapping better than stock 8-way?**
Stock 8-way provides all ten keypad digits through directions, Fire and Extra;
the consistent 1P routing below should make both pads accessible to one person.
Audit existing profiles and classify each verified game in this order:

1. **Stock 8-way:** use it whenever it covers setup and play adequately.
2. **8-way with custom buttons:** retain all eight directions and change only
   Fire/Extra/Start where that improves play. Check whether reassigned buttons
   remove access to a digit needed during setup or play.
3. **Custom control layout:** only when both eight-way options are demonstrably
   worse. Group by verified control needs, sometimes a single game or an
   author's shared layout. Freeway, Doodle and Robson's games are candidates;
   each still needs to justify its exception.

Record the concrete benefit over both simpler options for every custom profile.
Account for keypad routing separately before creating a mapping variant, and
consolidate games that need the same directions and button assignments. Evaluate
renaming `Homebrew` to `Robson`: it represents Paul Robson's controls, not a
generic homebrew layout; review `2P Homebrew` naming and coverage as well.

- One-player Gunfighter is confirmed working. Complete the remaining
  Tennis/Squash and Gunfighter/Moonship coverage: two-player Gunfighter, both
  controllers, Moonship diagonals, Squash's B-side racquet choice, the A-side
  ball-speed choices and routing changes during play.
- Verify Race Colour v1/v2 controls separately from Race.
- Audit Bowling/Baseball direction restrictions and alternating keypad roles;
  assess Robson games individually for setup digits and cross-pad actions.
- Keep Auto/1/2 for the initial cleanup, with consistent meanings: Auto uses
  the title's normal layout; 1P gives one controller access to both keypads,
  mirroring symmetric controls; 2P assigns controllers 1/2 to keypads A/B.
  Preserve documented controls spanning both pads in asymmetric games.
- Verify generic 8-way Auto's single-pad routing in play, including Pinball's
  B-side controls and switching Players 1/2. Audit remaining fallback titles
  for their normal keypad before treating their automatic mapping as complete.
- Require a documented gameplay or setup reason for restricting directions;
  specialized Fire/Extra assignments alone do not justify removing keypad
  directions. Check complete setup sequences, including Tennis/Squash racquet
  choices and A7/A8/A9 speed/start keys.
- Reassess the Gunfighter/Tennis merge against actual play, including Moonship
  Battle's eight directions. Identical current RTL outputs do not establish
  that two games need identical mappings.
- Verify normal play, one controller operating both sides, two controllers
  independently operating their pads, and switching routing without changing
  the selected game. Use these outcomes as regression expectations.
- Consider clearer Normal/Mirror labels later; the immediate priority is
  predictable behavior under the existing settings, not a menu redesign.

### Other keypad refinements

- Prevent the left analog stick from also generating ordinary profile movement
  while Numstick is using it to select `0`. Prefer automatic suppression while
  Numstick is active, unless an explicit left-stick option proves necessary.
- MPT-02 manuals confirm the optional joystick adaptor's `2/4/6/8` cardinals
  for Speedway/Tag and Star Wars. Verify other titles and the Fire/Extra buttons
  from primary material or hardware before generalizing that equivalence across
  the machine family. The matching Visicom layout is documented separately.

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

- Add two-entry, 1-bit palette support for Studio II foreground and background,
  keeping the hardware-accurate colours as the default.
- Consider an optional expanded eight-entry palette for Studio III after the
  Studio II and Visicom paths are settled. Studio III already has a carefully
  matched hardware default, and its colour banding makes this a lower priority.
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
