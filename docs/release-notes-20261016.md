# RCA Studio II for MiSTer

## October 16, 2026 release

This maintenance release follows the September 26 release. It fixes CHIP-8 startup without a BIOS, updates the upstream MiSTer framework, and includes small OSD, bundled software, and test improvements.

## Highlights

### BIOS-free CHIP-8 startup

- Fixed CHIP-8 programs remaining held in reset when no machine BIOS was loaded.
- Loading a CHIP-8 program now releases reset so the bundled OpenStudio2 interpreter can run independently of the machine BIOS.
- Normal reset, CLEAR, machine switching, and unload behavior are preserved. Visicom still requires its own firmware and does not support CHIP-8.

### Upstream MiSTer updates

- Updated `sys` with upstream scaler, analog-video, audio-output, and I/O-board changes.
- Included scaler recovery when PLL reconfiguration interrupts the output clock.
- Included Y/C chroma-pipeline and PAL/NTSC luma changes, registered audio outputs, and more stable I/O-board mode detection.

### OSD and bundled software

- Grayed out Load CHIP-8 while Visicom is active.
- Renamed the System submenu's interpreter loader to CHIP-8 Interpreter.
- Corrected MiSTer configuration-string formatting.
- Updated bundled Race DX from v1.05 to v1.10.
- Made small README clarifications.

## Additional engineering work

- Replaced the duplicated top-level port list with the upstream `sys/emu_ports.vh` interface.
- Added a reset regression using the real MiSTer core top level with HPS and PLL stubs.
- Fixed the regression runner to preserve failed build exit codes and stop immediately; added checks for this behavior.
- Updated test documentation and generated-file ignore entries.

## Testing and validation

- The top-level reset test passed, covering BIOS-free CHIP-8 startup, hard reset, CLEAR, machine switching, unload, and invalid interpreter handling.
- Six shell-tool checks and rebuilt headless loader, memory, CHIP-8, and Visicom checks passed.
- The Quartus build meets all reported timing checks with fitter seed 13. Worst setup slack is +0.322 ns; worst hold slack is +0.210 ns.

## Known limitations

- Studio IV is not supported.
- CHIP-8 is unavailable in Visicom mode.
- Marcel van Tongeren's optional interpreter retains its original memory limitations; bundled OpenStudio2 is recommended for normal CHIP-8 use.
- Direct analog video remains separately unverified.
