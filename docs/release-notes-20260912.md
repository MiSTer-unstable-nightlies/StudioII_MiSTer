# RCA Studio II for MiSTer

This is a major maturity release following the 2026-08-30 build. The core is now effectively feature-complete, with substantial improvements to CHIP-8 support, controls, video presentation, audio, cartridge handling, compatibility, documentation, and verification. It's been extensively hardware-tested.

## Highlights

### CHIP-8 is now built in

- OpenStudio2 is bundled with the core, so `.ch8` programs no longer require a separate `chip8.bin`.
- OpenStudio2 provides a dedicated 4 KB CHIP-8 memory space.
- Added the conventional COSMAC VIP keyboard layout:

  ```text
  1 2 3 4    →    1 2 3 C
  Q W E R    →    4 5 6 D
  A S D F    →    7 8 9 E
  Z X C V    →    A 0 B F
  ```

- The CHIP-8 keyboard layout activates only while a CHIP-8 program is running.
- Marcel van Tongeren’s original Studio II interpreter remains available as an optional manual replacement.

### Greatly improved controller support

- Expanded and audited automatic controller mappings across Studio II, Studio III/MPT-02, and Visicom software.
- The cartridge profile database now contains 166 exact-image CRC entries.
- Added or corrected mappings for resident firmware games, Grand Pack, Pinball, Climber, Outbreak, Gunfighter, Tennis, Race, Space Explorer, Visicom games, and numerous cartridge variants.
- Automatic mappings now select the appropriate keypad, game-start key, player routing, and special actions more reliably.
- Unknown cartridges continue to receive the general-purpose 8-way layout.
- Expanded the game-control documentation with verified startup sequences and control descriptions.

### New video and palette options

- Added a Borders On/Off option.
- Added an optional 216p vertical crop for clean 5× scaling at 1080p, with adjustable vertical positioning.
- Added Game Boy `.gbp` palette loading:
  - Two-color palettes for Studio II and CHIP-8.
  - Four-color palettes for Visicom.
- Included a set of ready-to-use Studio II and Visicom palettes.
- Updated the default Visicom colors to the balanced palette.
- Improved handling of blanking, cropping, scaling, and the full active raster.

### Refined audio emulation

- Completed the hardware-derived Studio II and Visicom NE555 beeper model.
- Improved pitch descent, release, retrigger behavior, amplitude envelope, and asymmetric waveform duty cycle.
- Added seven pitch choices to accommodate original-console variation:
  Original, High, Higher, Highest, Lowest, Lower, and Low.
- Added an optional PAL-equivalent pitch setting for the Studio III NTSC CDP1863 tone generator.
- Muting still preserves the live state of the underlying sound generator.

### Better cartridge and firmware handling

- Added **Unload Cartridge**, which ejects the current cartridge without resetting the machine.
- Added **Unload Cartridge and Reset** for a conventional eject-and-restart operation.
- Each machine now retains its own firmware and cartridge-related state while switching between Studio II, Studio III PAL, Studio III NTSC, and Visicom.
- Unloading a cartridge correctly returns to the remembered resident firmware or game mapping.
- Fixed cross-machine corruption that could occur after loading a Visicom cartridge.
- Improved cartridge page ownership, partial-image handling, open-bus behavior, and CHIP-8 unload behavior.

### Compatibility fixes

- Corrected Studio III NTSC display control: `OUT 1` now changes the background rather than disabling video.
- Improved Studio III Grand Pack resident-game selection.
- Corrected several Visicom resident-game profiles and controls.
- Fixed profile naming and numerous edge-case Start, Fire, Extra, keypad, and player assignments.
- Improved handling of repeated cartridge loads, machine changes, firmware replacement, reset, CLEAR, and unload operations.

## Additional engineering work

- Split the audio, controller mapping, and cartridge-profile logic into focused source units while preserving a unified hardware implementation.
- Consolidated the automated headless regression suite.
- Expanded directed coverage for cartridge loading, memory decoding, CHIP-8, Visicom memory ownership, controller input, display enable, and tone generation.
- Added a repeatable game-start screenshot sweep with exact-image identification, failure detection, and reviewed visual baselines.
- Improved stale-build, timeout, crash, and incomplete-simulation detection.
- Updated the bidirectional `.st2`/`.bin` conversion utility.
- Reworked and expanded the installation, control, gameplay, audio, video, development, and palette documentation.
- Removed obsolete test material, superseded scripts, private reference captures, and unrelated bundled software.
- Narrowed the included homebrew collection to the maintained color-enhanced releases.

## Testing and validation

- The latest RTL has undergone extensive testing on MiSTer hardware across supported machines, software, controls, audio, video, cartridge loading, firmware switching, and CHIP-8 operation.
- Automated RTL and headless regression coverage was also substantially expanded.
- Directed tests now cover cartridge loading, memory decoding, CHIP-8, Visicom memory ownership, controller input, display enable, and tone generation.
- A repeatable screenshot-based game-start sweep was added for exact-image compatibility testing and visual regression review.

## Known limitations

- Studio IV is not supported.
- CHIP-8 is unavailable in Visicom mode.
- Marcel van Tongeren’s optional interpreter retains its original memory limitations; bundled OpenStudio2 is recommended for normal CHIP-8 use.
- Direct analog video remains separately unverified.