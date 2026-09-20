# Development reference

Architecture, implementation constraints, verification scope, and build mechanics. `AGENTS.md` contains repository-wide coding rules. Keep transient investigations and release-specific notes out of this file.

Focused references:

- `docs/how-to-play.md` - game selection and keypad research.
- `docs/controller.md` - controller implementation and identification rules.
- `docs/beeper-status.md` - Studio II audio evidence and acceptance criteria.
- `docs/analog-video.md` - direct-video behavior and hardware test procedure.
- `roadmap.md` - planned work.

## Implemented machines

| Machine | Video | Sound | Notes |
|---|---|---|---|
| Studio II | CDP1861, NTSC mono | discrete beeper | primary target |
| Studio III PAL | CDP1864 | CDP1864 tone | 312-line PAL timing |
| Studio III NTSC | CDP1861 + CDP1862 | CDP1863 | 1861 timing with separate colour |
| Visicom COM-100 | CDP1861 + second DMA bitplane | NE555 compatibility beeper | separate memory map and indexed palette |

The core implements CPU and DMA video, raw and paged software loading, four native firmware slots, the CHIP-8 interpreter slot, machine-specific memory maps, controller profiles, on-screen keypad support, integer scaling, custom palettes, and sync-preserving same-standard resets.

The loader models 4 KB of software address space. Pages `$10+` are not supported.

The CDP1802 implements all four CLEAR/WAIT operating modes. LOAD holds S1 idle, services DMA through R(0), and returns to LOAD after each transfer. Software should pass through RESET before RUN so R(0) restarts at `$0000`.

## Main modules

`Studio-II.sv` is the MiSTer `emu` top. `rtl/rcastudioii.sv` contains the CPU integration, memory maps, software loader, keypad/controller mapping, and machine selection.

Important supporting modules:

- `rtl/cdp1802.v` - CDP1802 CPU.
- `rtl/audio/studio2_beeper.sv` - Studio II/Visicom NE555 beeper.
- `rtl/pixie/cdp1861.v` - Studio II, Studio III NTSC, and Visicom timing/DMA.
- `rtl/pixie/cdp1862.v` - Studio III NTSC colour.
- `rtl/pixie/cdp1863.v` - Studio III NTSC tone and shared divider model.
- `rtl/pixie/cdp1864.v` - Studio III PAL video, colour, and tone timing.
- `rtl/pixie/pixie_video.v` - CDP1861 wrapper.
- `rtl/studio2_palette.sv` - built-in presets, custom palette commits, and final RGB selection.
- `rtl/studio2_cart_profiles.svh` - CRC-to-controller-profile database.

## Clocking

`clk_sys` is about 7.040229 MHz. `ce_pix` divides it by four to the approximately 1.760 MHz machine timebase. CPU machine cycles occur every eight `ce_pix` pulses.

MiSTer video is resampled into `clk_vid` at about 42.24 MHz and presented to `video_mixer` at about 7.04 MHz, repeating each native pixel four times.

The Verilator harness normally holds `ce_pix` high. Use `--ce4` when reset release, CLEAR, DMA/CPU phase, or other clock-structure behavior matters. The harness instantiates `rtl/rcastudioii.sv`, not the MiSTer top, so it cannot prove HPS boot ordering, OSD masking, Apply classification, or top-level sync-preservation behavior.

## OSD and status ownership

Frequently used controls remain at the top level. Audio/video, palette, and replacement-firmware controls are grouped into submenus.

Relevant status fields:

| Field | Function |
|---|---|
| `status[5:2]` | manual joystick profile |
| `status[6]` | automatic/manual mapping |
| `status[8:7]` | player routing |
| `status[10:9]` | Numstick |
| `status[12:11]` | scaler mode |
| `status[14:13]` | staged machine selection |
| `status[15]` | Apply and Reset |
| `status[16]` | sound mute |
| `status[19:17]` | Studio II/Visicom NE555 pitch |
| `status[20]` | Studio III NTSC CDP1863 pitch |
| `status[21]` | 216p crop enable |
| `status[25:22]` | crop offset |
| `status[26]` | borders |
| `status[33:31]` | Studio II palette |
| `status[36:34]` | Visicom palette |
| `status[39:37]` | Studio III palette |

`status_menumask` hides controls that do not apply to the active machine. Custom palette loader rows appear only when the corresponding machine is active and its palette selector is set to Custom.

The System submenu contains Machine ROM and CHIP-8 Core replacement. Load Software, Load CHIP-8, Machine, Apply and Reset, Clear, Reset, Unload Software, and Unload Software and Reset remain at the top level.

## Audio

The Studio II/Visicom NE555 pitch selector provides Original, High, Higher, Highest, Lowest, Lower, and Low. Tuning scales the latched full oscillator period before the 11:6 phase split; it does not replace or restart the generator state.

The Studio III NTSC CDP1863 pitch selector provides native pitch or the CDP1864 divide-by-four stage for PAL-equivalent pitch. The same live generator state is retained when the divider selection changes.

Muting gates the final audio output. Tone generators continue running while muted.

## Palette model

Studio II and Visicom custom palettes use 16-byte MiSTer Game Boy `.gbp` files. Studio III custom palettes use eight sequential RGB888 entries in a headerless `.pal` file.

Custom palette data is staged and committed only after a complete file has arrived. Studio III commits after byte 23 and ignores trailing bytes. Palette loading never resets the machine.

Built-in selections are owned by `rtl/studio2_palette.sv`:

- Studio II: Original, Amber, Green, Inverted, Custom.
- Studio III: Original, Prototype, Warm, Cool, Custom.
- Visicom: Balanced, Box Art, Emma 02, FLiP, MAME, Manuals, Nicole Express, Custom.

## Video behavior

Studio III NTSC uses `INP 1` for display enable and `OUT 1` for the CDP1862 background step. The Studio II `OUT 1` display-off decode must not apply to Studio III NTSC. Studio III PAL retains `INP 4` display-off behavior.

The normal output path is:

```text
rcastudioii sync + blanking + RGB
    -> clk_sys/clk_vid resampling
    -> video_mixer (LINE_LENGTH=352)
    -> video_freak
    -> MiSTer framework
```

`video_mixer` derives raster DE from HBlank/VBlank. The core's `video_de` and `bitmap_de` are simulation/capture signals. Borders Off substitutes bitmap-window blanking without changing the device raster counters or HS/VS timing.

The CDP1861 path has 112 native pixel times and 262 lines per frame. Raster active starts at pixel 24 and is 88 pixels wide. Bitmap DMA occupies pixels 40-103. The authored 64-pixel bitmap window is therefore not centered within the full raster and should not be moved merely for presentation.

The CDP1864 path has 112 native pixel times, 312 lines, and a 192-line display. Switching between PAL and NTSC normally causes the display to resync.

`video_mixer.LINE_LENGTH` is 352, covering the full 88-pixel raster at 4x. VS is delayed by one `CE_PIXEL` only at the `video_freak` input so its active-line count survives the same-edge reset.

The optional 216-line crop applies only to an undoubled 1920x1080 scaler output. Other HDMI resolutions, Direct Video, and forced scandoubling leave it disabled. When borders are hidden, the original-aspect-ratio calculation compensates for the reduced active window rather than forcing the cropped bitmap to 4:3.

## Reset and machine selection

CPU/machine reset and raster reset are separate. `reset` restarts machine state; `video_reset` restarts raster counters and the CPU phase divider only for a hard reset.

| Event | Class | Raster behavior |
|---|---|---|
| Core load, MiSTer reset, unknown download | hard | restarts |
| Software load | sync-preserving | remains live |
| CHIP-8 load | sync-preserving | remains live |
| Machine ROM load | sync-preserving | remains live |
| CHIP-8 Core load | sync-preserving | remains live |
| Custom palette load | none | remains live |
| Same-standard Apply and Reset | sync-preserving | remains live |
| PAL/NTSC Apply and Reset | hard | restarts |
| CLEAR | sync-preserving | remains live |

Download type is latched through the post-download reset stretch because `ioctl_index` is valid only during transfer. Apply and Reset determines whether a machine change crosses video standards before updating `machine_active`. Hard reset sources dominate overlaps.

CLEAR is normal console operation, not a generic hard reset. Its special handling leaves the Studio III tone generator running.

## Firmware and download routes

The Machine field is staged until **Apply and Reset**, apart from the boot-follow path used to restore saved settings.

| Machine | File |
|---|---|
| Studio II | `boot0.rom` |
| Studio III PAL | `boot1.rom` |
| Studio III NTSC | `boot2.rom` |
| Visicom | `boot3.rom` |
| CHIP-8 interpreter | bundled OpenStudio2; optional F4 override |

Studio II firmware is normally 2 KB. Each resident firmware BRAM is 4 KB so Studio III firmware fits. F2 writes the active machine slot.

The fifth BRAM starts with bundled OpenStudio2. F4 replaces that shared interpreter bank with a manually loaded Marcel or OpenStudio2 image. Loading an interpreter does not itself enter CHIP-8 mode. Ordinary reset, unload, and machine changes retain the override; reloading the core restores the bundled image.

The low six bits of `ioctl_index` select the user download route:

| Index | OSD action | Format | Reset behavior |
|---:|---|---|---|
| `0` | boot firmware/autoload | ROM | hard during core boot |
| `1` | Load Software | `.st2`, `.bin`, `.rom` | sync-preserving soft reset |
| `2` | Load Machine ROM | `.bin`, `.rom` | sync-preserving soft reset |
| `3` | Load CHIP-8 | `.ch8` | sync-preserving soft reset |
| `4` | Load CHIP-8 Core | `.bin`, `.rom` | sync-preserving soft reset |
| `5` | Visicom custom palette | `.gbp` | none |
| `6` | Studio II custom palette | `.gbp` | none |
| `7` | Studio III custom palette | `.pal` | none |

## Memory and software loading

Studio II / Studio III NTSC base map:

- `$0000-$07FF`: firmware/resident games.
- `$0800-$09FF`: 512-byte RAM.
- `$0A00-$0BFF`: cartridge window.
- `$0C00-$0DFF`: RAM mirror unless paged software owns it.
- `$0E00-$0FFF`: cartridge window.
- Undecoded reads return `$FF`.

Studio III may use 4 KB firmware and has 64 mirrored 3-bit colour cells in `$0B00-$0BFF`. CPU reads return the stored colour in bits 2:0 with bits 7:3 clear. CPU access uses the low six address bits; DMA uses `{offset[7:5], offset[2:0]}`.

Visicom uses `$0000-$07FF` for resident ROM, `$0800-$0FFF` for the loaded cartridge, `$1000-$11FF` for RAM/plane 0, `$1300-$13FF` for plane 1, and leaves `$1200-$12FF` empty. Omitted cartridge pages read as open bus (`$FF`).

Raw `.bin`/`.rom` images load from `$0400` on Studio machines and `$0800` on Visicom.

`.st2` files are detected by `RCA2` magic and use the header page table. On Studio II and Studio III, valid mapped pages `$00-$07` may overlay resident ROM without modifying firmware BRAM. Pages `$0C/$0D` may replace the normal RAM mirror. Pages `$08-$09` remain RAM and are rejected; Studio III also reserves colour page `$0B`. Visicom accepts only cartridge pages `$08-$0F`. Pages `$10+` are dropped.

Unloading clears page ownership and exposes resident firmware again.

Controller automapping hashes the exact downloaded bytes with CRC16-CCITT, polynomial `0x1021`, initial value `0xFFFF`. Headered and raw representations therefore have different CRCs even when their program payloads match.

## CHIP-8

With bundled OpenStudio2, `.ch8` bytes `$000-$DFF` load at offsets `$200-$FFF` in separate 4 KB CHIP-8 RAM mapped to CPU `$1000-$1FFF`. Later bytes are dropped. Interpreter ROM remains in the fifth ROM bank.

With a Marcel override, `.ch8` bytes `$000-$4FF` map to physical ROM `$0300-$07FF`; bytes `$500-$8FF` map to `$0C00-$0FFF`; later bytes are dropped. This path is unavailable on Visicom.

Marcel's interpreter has a virtual program ceiling of `$0AFF` and only a small translated writable-RAM window. Software that relies on broader writable or self-modifying CHIP-8 memory should use OpenStudio2 instead.

## Hardware-derived constraints

- Studio II has 512 bytes of paired nibble RAM. Bitmap memory runs from `$0900` at top left through `$09FF` at bottom right, eight bytes per logical row, bit 7 leftmost.
- The physical data bus has pull-ups, supporting open-bus reads of `$FF`.
- Physical keypad selection is `N1 AND TPB`; software uses `OUT 2`.
- CDP1861 requests eight DMA-OUT cycles for each displayed scanline and the CPU supplies bytes through R0.
- Studio II is NTSC-only and uses an adjusted RC oscillator; the approximately 1.760 MHz core clock is a practical hardware-derived model, not an exact crystal constant.
- CDP1861/CDP1864 EF timing deliberately leads nominal line boundaries. Interrupt and DMA requests are accepted at instruction boundaries, and DMA remains asserted until serviced.
- `CON` is captured with each luminance DMA byte.
- Studio III NTSC is a CDP1861 + CDP1862 + CDP1863 machine, not a retimed CDP1864 implementation.
- In the CPU Cx row, `C4` is NOP and `C5-C7`/`CC-CF` are long skips.

## Verification

No single test establishes overall accuracy:

| Evidence | Establishes | Does not establish |
|---|---|---|
| Directed RTL tests | asserted decode/port/mirror behavior | untested timing or FPGA inference |
| `tools/refemu` | repeatable CPU/bitmap comparisons | cycle-accurate EF/DMA timing or independent truth |
| Other emulators | useful second implementation | independence from shared models |
| Primary docs and hardware | physical constraints and measured behavior | corpus-wide regression |
| Quartus reports | inference, fit, timing closure | runtime correctness |
| MiSTer testing | complete built integration | exhaustive internal state |

Canonical paths are `rom/` for firmware, `software/` for the corpus, `tools/refemu/` for the reference emulator, `verilator/obj_dir_headless/Vtop` for the headless model, and `out/` for generated captures. `refs/` is optional research material and must not be a normal build dependency.

Primary directed checks include:

- `tools/memdecode-test.sh`
- `tools/chip8-loader-test.sh`
- `tools/visicom-loader-test.sh`
- `tools/tone-test.sh`
- `tools/verify-beeper.sh`
- `make -C verilator cpu-load-test`
- `make -C verilator palette-test`

`tools/rtl-regression.sh` rebuilds the headless and CPU-only models, runs the LOAD test, and then runs the headless smoke suite. Use targeted tests while developing and the full regression before release.

`tools/game-start-sweep.py` remains available for exact-image startup and screenshot regression work. Its output is evidence of repeatability for the tested image, machine, input sequence, and capture settings; it is not proof of complete gameplay accuracy.

## Building

The project targets Quartus 17.0.x. The normal local flow is to open `Studio-II.qpf` and compile in Quartus. After RAM-related changes, inspect `output_files/Studio-II.map.rpt` for the expected `altsyncram` inference.

The Verilator headless model is built with:

```sh
make -C verilator headless
```

The Docker Quartus helper remains a separate optional workflow. Do not encode maintainer-specific local installation paths into repository scripts or documentation.

## References and provenance

When timing or device behavior is ambiguous, combine RCA/Weisbecker primary material with independent implementations and hardware evidence. Useful references include MAME, Emma 02, Paul Robson's emulator and software, Andrew Modla's `rca-studio2`, Eric Smith's COSMAC VHDL, dmadole's AVI1861, and real hardware captures.

The original core is by Jason Coombes, with MiSTer integration and early Pixie work by Flandango. Alan Steremberg carried later CPU/DMA/video and machine-support work. Elle Ball contributed controller profiles, OSD and scaling work, sync-preservation changes, research, and hardware testing.

Accuracy work also relies on Paul Robson, MAME contributors, Marcel van Tongeren, Andrew Modla, Eric Smith, dmadole, kanpapa, RCA documentation, community hardware research, Kevin Bunch's reference captures and hardware insight, and Hagley Museum and Library preservation work.

The project is GPL-2.0-or-later. OpenStudio2 is MIT. Reference-emulator sources under `tools/refemu/` are not compiled into the core.
