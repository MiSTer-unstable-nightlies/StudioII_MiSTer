# RCA Studio II for MiSTer

## Unstable build - September 19, 2026

This build follows the September 12 release and focuses on palette handling, software loading, Studio III compatibility, CDP1802 behavior, controller profiles, and repository cleanup.

## Highlights

### Reworked OSD

- Added dedicated **Audio & Video**, **Palettes**, and **System** submenus.
- Kept frequently used controls at the top level: Load Software, Load CHIP-8, Machine, Apply and Reset, Mapping, Joystick, Players, Numstick, Clear, Reset, and unload actions.
- Renamed **Load Cartridge** to **Load Software** because the loader now accepts more than conventional cartridge layouts.
- Renamed the unload actions to **Unload Software** and **Unload Software and Reset**.
- Kept Machine ROM and CHIP-8 Core replacement in the System submenu.

### Expanded palette support

- Added built-in palette selection for Studio II, Studio III, and Visicom.
- Studio II presets: Original, Amber, Green, Inverted, and Custom.
- Studio III presets: Original, Prototype, Warm, Cool, and Custom.
- Visicom presets: Balanced, Box Art, Emma 02, FLiP, MAME, Manuals, Nicole Express, and Custom.
- Added Studio III custom palette loading using headerless 24-byte RGB888 `.pal` files.
- Studio II and Visicom custom palettes continue to use MiSTer Game Boy `.gbp` files.
- Custom palette loaders appear only when the corresponding machine is active and **Custom** is selected.
- Palette changes take effect without resetting the running machine.
- Reorganized the included palette collection and added new Studio II, Studio III, and Visicom examples.

### Broader `.st2` software loading

- Extended `.st2` page handling so Studio II and Studio III packages can map low ROM pages permitted by the format.
- Bare-metal `.st2` software can now replace resident ROM pages without modifying the firmware BRAM.
- Raw `.bin`/`.rom` loading behavior remains unchanged.
- Unloading software removes cartridge page ownership and reveals the resident firmware again.

### CPU and Studio III compatibility fixes

- Implemented CDP1802 LOAD-mode behavior, including DMA through R(0) and proper RESET-to-RUN sequencing.
- Added CPU-visible Studio III colour-RAM readback in `$0B00-$0BFF`.
- The colour-RAM fix restores software that reads back colour values, including Paul's Printer.
- Corrected original-aspect-ratio handling when borders are hidden.

### Controller profiles and software updates

- Added and corrected exact-image CRC profiles for additional archival images and patched software.
- Improved Visicom automatic mappings, including Space Command, Reikan, and Sansuu Drill.
- Added current hashes for revised Invaders Colour, Pacman Visicom, Hockey Visicom, and Race DX images.
- Updated the bundled colour-enhanced homebrew set to the current maintained revisions.

## Engineering and verification

- Moved palette selection and custom-file handling into a dedicated `rtl/studio2_palette.sv` module.
- Added directed palette tests covering presets, custom loading, Studio III RGB888 input, and Visicom ordering.
- Added a CPU-only LOAD-mode regression covering DMA-IN, DMA-OUT, interrupt suppression, R(0) advancement, and RESET-to-RUN behavior.
- Expanded headless loader/input regression coverage for controller profiles and software-loading paths.
- Added a consolidated RTL regression entry point.
- Removed obsolete test scripts and stale repository material.
- Simplified cleanup scripts and refreshed development, controller, gameplay, palette, and analog-video documentation.

## Known limitations

- Studio IV is not supported.
- CHIP-8 is unavailable in Visicom mode.
- Marcel van Tongeren's optional interpreter retains its original memory limitations; bundled OpenStudio2 is recommended for normal CHIP-8 use.
- Direct analog video remains separately unverified.
