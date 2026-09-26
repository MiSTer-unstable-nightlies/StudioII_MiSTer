# RCA Studio II for MiSTer

## September 26, 2026 release

This release follows the September 12 launch release and folds in the later palette, software-loading, controller-profile, compatibility, and documentation updates made through September 26. It brings the core to a substantially mature state while preserving the hardware-focused behavior and feature set of the original RCA Studio II / Studio III / Visicom machine families.

## Highlights

### Reworked OSD and configuration layout

- Added dedicated Audio & Video, Palettes, and System submenus.
- Kept the frequently used controls at the top level: Load Software, Load CHIP-8, Machine, Apply and Reset, Mapping, Joystick, Players, Numstick, Clear, Reset, and unload actions.
- Renamed Load Cartridge to Load Software because the loader now accepts more than conventional cartridge layouts.
- Renamed the unload actions to Unload Software and Unload Software and Reset.
- Kept Machine ROM and CHIP-8 Core replacement in the System submenu.

### Expanded palette support

- Added built-in palette selection for Studio II, Studio III, and Visicom.
- Studio II presets: Original, Amber, Green, Inverted, and Custom.
- Studio III presets: Original, Prototype, Warm, Cool, and Custom.
- Visicom presets: Balanced, Box Art, Emma 02, FLiP, MAME, Manuals, Nicole Express, and Custom.
- Added Studio III custom palette loading using headerless 24-byte RGB888 `.pal` files.
- Studio II and Visicom custom palettes continue to use MiSTer Game Boy `.gbp` files.
- Custom palette loaders appear only when the corresponding machine is active and Custom is selected.
- Palette changes take effect without resetting the running machine.
- Reorganized the included palette collection and added new Studio II, Studio III, and Visicom examples.

### Broader `.st2` software loading

- Extended `.st2` page handling so Studio II and Studio III packages can map low ROM pages permitted by the format.
- Bare-metal `.st2` software can now replace resident ROM pages without modifying the firmware BRAM.
- Raw `.bin` / `.rom` loading behavior remains unchanged.
- Unloading software removes cartridge page ownership and reveals the resident firmware again.

### CPU and Studio III compatibility fixes

- Implemented CDP1802 LOAD-mode behavior, including DMA through R(0) and proper RESET-to-RUN sequencing.
- Added CPU-visible Studio III colour-RAM readback in `$0B00-$0BFF`.
- The colour-RAM fix restores software that reads back colour values, including Paul's Printer.
- Corrected original-aspect-ratio handling when borders are hidden.
- Improved firmware and software loading behavior while preserving the intended machine-reset and cartridge-unload semantics.

### Controller profiles and software updates

- Added and corrected exact-image CRC profiles for additional archival images and patched software.
- Improved Visicom automatic mappings, including Space Command, Reikan, and Sansuu Drill.
- Added current hashes for revised Invaders Colour, Pacman Visicom, Hockey Visicom, and Race DX images.
- Updated the bundled colour-enhanced homebrew set to the current maintained revisions.
- Continued to expand and audit automatic controller mappings across Studio II, Studio III/MPT-02, and Visicom software.

### Repository cleanup and documentation refresh

- Removed obsolete test material, superseded scripts, stale repository content, and unrelated bundled software.
- Narrowed the included homebrew collection to the maintained color-enhanced releases.
- Simplified cleanup scripts and refreshed the installation, controller, gameplay, palette, and analog-video documentation.
- Updated the bidirectional `.st2` / `.bin` conversion utility.

## Additional engineering work

- Moved palette selection and custom-file handling into a dedicated `rtl/studio2_palette.sv` module.
- Added directed palette tests covering presets, custom loading, Studio III RGB888 input, and Visicom ordering.
- Added a CPU-only LOAD-mode regression covering DMA-IN, DMA-OUT, interrupt suppression, R(0) advancement, and RESET-to-RUN behavior.
- Expanded headless loader and input regression coverage for controller profiles and software-loading paths.
- Added a consolidated RTL regression entry point.
- Split the audio, controller mapping, and cartridge-profile logic into focused source units while preserving a unified hardware implementation.
- Consolidated and streamlined the automated headless regression suite.

## Testing and validation

- The latest RTL has undergone extensive testing on MiSTer hardware across supported machines, software, controls, cartridge loading, firmware switching, palette handling, and CPU compatibility.
- Automated RTL and headless regression coverage was substantially expanded.
- Directed tests now cover cartridge loading, memory decoding, CHIP-8, Visicom memory ownership, controller input, display enable, tone generation, palette behavior, and LOAD-mode CPU behavior.
- A repeatable screenshot-based game-start sweep was added for exact-image compatibility testing and visual regression review.

## Known limitations

- Studio IV is not supported.
- CHIP-8 is unavailable in Visicom mode.
- Marcel van Tongeren’s optional interpreter retains its original memory limitations; bundled OpenStudio2 is recommended for normal CHIP-8 use.
- Direct analog video remains separately unverified.
