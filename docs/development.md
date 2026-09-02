# Development reference

Architecture, verification scope, and build mechanics live here. `AGENTS.md` contains permanent repository rules. Current RTL defines what is implemented; primary documentation and measured hardware define the target.

Read the focused references when relevant:

- `docs/how-to-play.md` — game selection and keypad research.
- `docs/controller.md` — controller implementation and identification rules.
- `docs/beeper-status.md` — Studio II audio evidence and current acceptance criteria.
- `docs/analog-video.md` — direct-video behavior and hardware test procedure.
- `roadmap.md` — planned work.

## Implemented machines

| Machine | Video | Sound | Notes |
|---|---|---|---|
| Studio II | CDP1861, NTSC mono | discrete beeper | primary target |
| Studio III PAL | CDP1864 | CDP1864 tone | 312-line PAL timing |
| Studio III NTSC | CDP1861 + CDP1862 | CDP1863 | 1861 timing with separate colour |
| Visicom COM-100 | CDP1861 + second DMA bitplane | NE555 compatibility beeper | separate memory map and fixed palette |

The CPU, DMA video, raw and paged cartridges, four native firmware slots plus the CHIP-8 interpreter slot, machine memory maps, controller profiles, on-screen keypad, integer scaling, and sync-preserving same-standard resets are implemented. The loader intentionally models only 4 KB of cartridge address space; high-page diagnostics such as ST3CTA Tester 3 remain unsupported.

## Module and clock map

`Studio-II.sv` is the MiSTer `emu` top. `rtl/rcastudioii.sv` contains the CPU, memory maps, cartridge loader, keypad/controller mapping, Studio II beeper, and machine selection.

The Studio II/Visicom NE555 pitch selector occupies `status[19:17]`. Codes 0--6
are Original, High, Higher, Highest, Lowest, Lower, and Low; unused code 7
decodes to Original. Low/High, Lower/Higher, and Lowest/Highest apply one, three,
and six cumulative steps of the original reciprocal 31:32 frequency ratio.
Tuning scales the latched full oscillator period before its 11:6 phase split,
leaving the accepted state trajectory and all time-domain envelope behavior
unchanged.
The OSD exposes the selector for Studio II and Visicom and hides it for both
Studio III variants.

The Studio III NTSC tone-pitch selector occupies `status[20]`. Zero keeps the
standalone CDP1863's native pitch; one selects the CDP1864 divide-by-four stage
and matches PAL pitch. The OSD enables the field only when the active machine is
Studio III NTSC. It changes only the divider-stage input to the shared generator,
so the latch, counter, output phase, and reset behavior remain a single live state.

Video crop enable occupies `status[21]`, crop offset `status[25:22]`, and border
hiding `status[26]`. The crop follows the common NES/SNES MiSTer convention: it
is enabled only for an un-doubled 1920x1080 scaler output and supplies a 216-line
window to `video_freak`. Border hiding selects bitmap-window blanking while
leaving device counters and HS/VS unchanged.

Live video modules:

- `rtl/pixie/cdp1861.v` — Studio II, Studio III NTSC, and Visicom timing/DMA.
- `rtl/pixie/cdp1862.v` — Studio III NTSC colour.
- `rtl/pixie/cdp1863.v` — Studio III NTSC tone and shared divider model.
- `rtl/pixie/cdp1864.v` — Studio III PAL video, colour, and tone timing.
- `rtl/pixie/pixie_video.v` — 1861 wrapper.

`clk_sys` is about 7.040229 MHz. `ce_pix` divides it by four to the approximately 1.760 MHz machine timebase; CPU machine cycles occur every eight `ce_pix` pulses. MiSTer video is resampled into `clk_vid` at about 42.24 MHz and presented to `video_mixer` at about 7.04 MHz, repeating each native pixel four times.

The Verilator harness normally holds `ce_pix` high. Use `--ce4` for reset release, CLEAR, DMA/CPU phase, or other clock-structure work, `--press-phase N` to sweep phase-sensitive input, `--beeper-tune medium|high|higher|highest|lowest|lower|low` to select the Studio II tuning (`medium` selects Original), and `--ntsc-tone-pitch original|pal` to select the Studio III NTSC pitch. The harness instantiates `rtl/rcastudioii.sv`, not the MiSTer top, so it cannot prove HPS boot ordering, Apply classification, OSD menu masking, or F1/F2 sync preservation.

## Video behavior

The normal output path is:

```text
rcastudioii sync + blanking + RGB
    -> clk_sys/clk_vid resampling
    -> video_mixer (LINE_LENGTH=352)
    -> video_freak
    -> MiSTer framework
```

`video_mixer` derives raster DE from HBlank/VBlank. The core's
`video_de`/`bitmap_de` is only for simulation and bitmap capture.
The top level may instead present the bitmap-specific HBlank/VBlank when Borders
is Off; this changes the active window without changing raster or sync timing.

The CDP1861 path has 112 native pixel times and 262 lines per frame. Raster active starts at pixel 24 and is 88 pixels wide. Bitmap DMA occupies pixels 40–103, leaving the authored window 16 pixels from the raster's left edge and eight from the right. Do not move the bitmap window to centre it; adjust porches/blanking and revalidate timing instead.

The CDP1864 path has 112 native pixel times, 312 lines, and a 192-line display. Switching between PAL and NTSC will generally make the display resync; this is expected.

Integer scaling depends on two top-level integration details:

1. `video_mixer.LINE_LENGTH` is 352, the full 88-pixel raster width x4 and the
   maximum needed when the optional 64-pixel borderless window is selected.
2. VS is delayed by one `CE_PIXEL` only on the `video_freak` input so its final active-line count is not overwritten by a same-edge reset.

The OSD exposes scale modes 0–3 with `.SCALE({1'b0, status[12:11]})`; mode 4 is intentionally absent.
At a 1920x1080 scaler resolution, the optional 216-line vertical crop permits
the existing integer modes to select 5x vertically. Crop offset uses the standard
MiSTer `0, 2, 4, 8, 10, 12, -12, -10, -8, -6, -4, -2` choices. Other HDMI
resolutions, Direct Video, and forced scandoubling leave vertical crop disabled.

## Reset and machine selection

CPU/machine reset and raster reset are separate. `reset` restarts machine state; `video_reset` restarts raster counters and the CPU phase divider only for a hard reset.

| Event | Class | Raster behavior |
|---|---|---|
| Core load, MiSTer reset, unknown download | hard | restarts |
| Cartridge load (F1) | sync-preserving | remains live |
| CHIP-8 load (F3) | sync-preserving | remains live |
| Manual firmware load (F2) | sync-preserving | remains live |
| Manual CHIP-8 interpreter load (F4) | sync-preserving | remains live |
| Same-standard Apply and reset | sync-preserving | remains live |
| PAL/NTSC Apply and reset | hard | restarts |
| CLEAR | sync-preserving | remains live |

Download type remains latched through the post-download reset stretch because `ioctl_index` is valid only during transfer. Apply/reset records whether the requested machine crosses standards before changing `machine_active`. Hard reset sources always dominate overlaps. CLEAR is normal console operation; its special case leaves the Studio III tone generator running.

The Machine OSD field is staged until **Apply and reset**, except for the short boot-follow path used to restore saved settings. Firmware slots are:

| Machine | File |
|---|---|
| Studio II | `boot0.rom` |
| Studio III PAL | `boot1.rom` |
| Studio III NTSC | `boot2.rom` |
| Visicom | `boot3.rom` |
| Marcel's CHIP-8 interpreter | F3 companion or F4 manual cache (`chip8.bin`) |

Studio II firmware is normally 2 KB; each resident BRAM is 4 KB so Studio III firmware fits. F2 writes the active machine's slot. MiSTer Main autoloads `boot0.rom` through `boot3.rom`, using index `[7:6]` for those four slots. The lowercase `f,!chip8.bin` entry immediately before F3 asks Main to send `chip8.bin` from the selected `.ch8` file's directory at supplemental index `$0103`; F4 sends a manually selected `.bin` at `$0004`. Either path caches a complete 768-byte interpreter in the fifth 4 KB BRAM, which also holds the loaded game. Loading the interpreter does not activate CHIP-8 by itself; the F3 main program follows at `$0003` and is rejected unless the cached image completed. The manual cache lasts for the core session and lets one interpreter serve programs in multiple directories. F3 is disabled on Visicom.

## Memory and cartridge model

Studio II / Studio III NTSC base behavior:

- `$0000-$07FF`: firmware/resident games.
- `$0800-$09FF`: 512-byte RAM.
- `$0A00-$0BFF`: cartridge window.
- `$0C00-$0DFF`: RAM mirror unless paged cartridge ROM owns it.
- `$0E00-$0FFF`: cartridge window.
- Undecoded reads return `$FF`.

Studio III may use 4 KB firmware and has 64 mirrored 3-bit colour cells in `$0B00-$0BFF`. A DMA offset selects `{offset[7:5], offset[2:0]}`, so one cell covers eight pixels by four logical bitmap rows.

Visicom uses `$0000-$07FF` for resident ROM and `$0800-$0FFF` for the current cartridge, `$1000-$11FF` for 512-byte RAM and plane 0, `$1300-$13FF` for plane 1, and leaves `$1200-$12FF` empty. Cartridge pages omitted by the current image read as open bus (`$FF`), even if an earlier cartridge wrote those BRAM locations. Its two plane bits select one of four fixed colours.

Raw `.bin`/`.rom` images load from `$0400` on Studio machines and `$0800` on Visicom. `.st2` is detected from `RCA2` magic and uses its header page table. Page ownership permits cartridge pages `$0C/$0D` to replace the normal RAM mirror. Studio II rejects system pages `$00-$03` and RAM pages `$08-$09`; Studio III also reserves colour page `$0B`; Visicom accepts only its cartridge pages `$08-$0F`, preserving resident pages `$00-$07`. Pages `$10+` are dropped.

F3 `.ch8` bytes `$000-$4FF` map to physical ROM `$0300-$07FF`; bytes
`$500-$8FF` map to `$0C00-$0FFF`; bytes from `$900` onward are dropped. This
path requires a complete cached `chip8.bin`, loaded automatically or manually,
and rejects Visicom in RTL as well as in the OSD.
Activation selects the fifth ROM on Studio II and both Studio III variants,
without changing the native RAM or Studio III colour-RAM windows. CLEAR, Reset,
and machine switches retain the game; F1, F2, and either interpreter-loading
path exit CHIP-8 mode. Loading a replacement interpreter also clears the prior
program before the replacement arrives.

[Marcel van Tongeren's interpreter map](https://www.emma02.hobby-site.com/studio_chip8.html)
accounts for the complete physical 4 KB bank:

| Studio address | Interpreter use | CHIP-8 view |
|---|---|---|
| `$0000-$02FF` | Interpreter | — |
| `$0300-$07FF` | First program window | `$0200-$06FF` |
| `$0800-$089F` | Writable game RAM | `$0B00-$0B9F` through `I` translation |
| `$08A0-$08CF` | CHIP-8 stack | — |
| `$08D0-$08EF` | Interpreter work area | — |
| `$08F0-$08FF` | Registers V0–VF | — |
| `$0900-$09FF` | Display RAM | — |
| `$0A00-$0BFF` | Unused by the interpreter | — |
| `$0C00-$0FFF` | Second program window | `$0700-$0AFF` |

Thus the program address ceiling is virtual `$0AFF`: a conventional `.ch8`
file begins at `$0200`, so its supported payload is `$900` bytes at file offsets
`$000-$8FF`. JP and CALL cannot target virtual `$0800-$0BFF`. Writes through
`I` are translated into the small `$0B00-$0B9F` virtual RAM window and are only
compatible with simple RAM use; software depending on broader or
self-modifying program memory generally needs adaptation.

Controller automapping hashes exact downloaded bytes using CRC16-CCITT, polynomial `0x1021`, initial value `0xFFFF`. Headered and raw forms have different CRCs even when their payloads match.

## Controllers

Controller architecture and profile identification are documented in
`docs/controller.md`. Game-control evidence belongs in `docs/how-to-play.md`.

## Hardware-derived constraints

- The Studio II has 512 bytes of paired nibble RAM; bitmap memory runs from `$0900` at top left through `$09FF` at bottom right, eight bytes per logical row, bit 7 leftmost.
- The physical data bus has pull-ups, supporting open-bus reads of `$FF`.
- Physical keypad selection is `N1 AND TPB`; software uses `OUT 2`, which is what the core decodes.
- The CDP1861 requests eight DMA-OUT cycles for each displayed scanline and the CPU supplies bytes through R0. Software repeats 32 logical bitmap rows into 128 active bitmap lines.
- The Studio II is NTSC-only and uses an adjusted RC oscillator; its approximately 1.760 MHz clock is a practical model, not an exact crystal constant.
- CDP1861/CDP1864 EF timing leads nominal line boundaries deliberately. Interrupt and DMA requests are accepted at instruction boundaries, DMA remains asserted until serviced, and parity adaptation may move service by one machine cycle.
- `CON` is captured with each luminance DMA byte. Studio III NTSC is a 1861+1862+1863 machine, not a retimed 1864; its native 1863 tone is four times the 1864-integrated tone for the same latch. The optional PAL-pitch setting selects the shared model's divide-by-four stage without resetting or duplicating generator state.
- In the CPU Cx row, `C4` is NOP and `C5-C7`/`CC-CF` are long skips.

## Verification and local layout

No single test establishes overall accuracy:

| Evidence | Establishes | Does not establish |
|---|---|---|
| Directed RTL tests | asserted decode/port/mirror behavior | untested timing or FPGA inference |
| `tools/refemu` | repeatable CPU/bitmap comparisons | cycle-accurate EF/DMA timing or independent truth |
| Other emulators | useful second implementation | independence from shared models |
| Primary docs and hardware | physical constraints and measured behavior | corpus-wide regression |
| Quartus reports | inference, fit, timing closure | runtime correctness |
| MiSTer testing | complete built integration | exhaustive internal state |

Canonical paths are `rom/` for firmware, `software/` for the corpus, `tools/refemu/` for the reference emulator, `verilator/obj_dir_headless/Vtop` for the headless model, and `out/` for generated captures. `refs/` is optional research material and must not be a normal build dependency. Scripts derive the repository root from their own location; never embed a maintainer's private path.

Quartus commands are `tools/quartus-build.sh`, `tools/quartus-build.sh map`, and `tools/quartus-build.sh clean`. The script uses the amd64 Quartus 17 container with `--parallel=1`, which is required under Apple Silicon emulation. After RAM changes, inspect `output_files/Studio-II.map.rpt` for inferred `altsyncram` instances.

Directed checks include `tools/memdecode-test.sh`, `tools/chip8-loader-test.sh`, `tools/visicom-loader-test.sh`, `tools/tone-test.sh`, `tools/visicom-test.sh`, and `tools/verify-beeper.sh`. The older corpus sweeps are diagnostics, not release gates.

## References and provenance

When timing is ambiguous, combine RCA/Weisbecker primary material, MAME, Emma 02, Paul Robson's emulator and software, Andrew Modla's `rca-studio2`, Eric Smith's COSMAC VHDL, dmadole's AVI1861, and real hardware evidence.

The original core is by Jason Coombes, with MiSTer integration and early Pixie work by Flandango. Alan Steremberg carried later CPU/DMA/video and machine-support work. Elle Ball contributed controller profiles, OSD and scaling work, sync-preservation changes, research, and hardware testing.

Accuracy work also relies on Paul Robson, MAME contributors, Marcel van Tongeren, Andrew Modla, Eric Smith, dmadole, kanpapa, RCA documentation, and community hardware research. Special thanks to Kevin Bunch for reference captures and hardware insight, and to the Hagley Museum and Library for preservation work.

The project is GPL-2.0-or-later. Reference-emulator sources under `tools/refemu/` are not compiled into the core.
