# RCA Studio II for MiSTer

MiSTer FPGA core for the RCA Studio II, Studio III/MPT-02 family, and Toshiba Visicom COM-100.

Example hardware units:
* RCA Studio II
* RCA Studio III (unreleased)
* Academy Apollo 80
* Conic M-1200
* Hanimex MPT-02
* Mustang 9016
* Sheen M-1200
* Soundic Victory (MPT-02)
* Toshiba Visicom COM-100
* Trevi M-1200

## Install and play

Copy the release `.rbf` to e.g. `/media/fat/_Console/` on MiSTer.

Put the four native firmware files below in `/media/fat/games/Studio-II/`.

Put the user-supplied `chip8.bin` in the same directory as your CHIP-8 games
for automatic loading, or load it manually.

Launch the core from `/_Console/` (or wherever you placed it).

Use **Load Cartridge** for a `.st2`, `.bin`, or `.rom` game, or **Load
CHIP-8** for a classic `.ch8` program. Use **Load Firmware** only to replace
the active machine's native firmware temporarily; use **Load CHIP-8
Interpreter** only for the separate `chip8.bin` cache.

`Machine` selects between `Studio II`, `Studio III (PAL)`, `Studio III (NTSC)`, and `Visicom`, in that order. Changes won't take effect until you `Apply and reset`.

| Machine | Autoload filename | Common filename | Size | MD5 |
|---|---|---|---:|---|
| Studio II | `boot0.rom` | `studio2.rom` | 2 KB | `B37205BF19B197682F00619D05DA194B` |
| Studio III PAL | `boot1.rom` | `studio3_pal.bin` | 4 KB | `A6B94E449BC9EC58A30E1F75D590C558` |
| Studio III NTSC | `boot2.rom` | `studio3_ntsc.bin` | 4 KB | `849A484AA4B2784ECE5C35C39D9D51A8` |
| Visicom | `boot3.rom` | `visicom.rom` | 2 KB | `AEEC6FE3934481E20EB7DB6D5FF56A54` |
| CHIP-8 interpreter | `chip8.bin` | `chip8.bin` | 768 bytes | `9F037435B6721BE9EE91DC93293E52CE` |

[Marcel van Tongeren's Studio-family interpreter](https://www.emma02.hobby-site.com/studio_chip8.html) 
`chip8.bin` is required for CHIP-8 support. You can find a copy in the Emma 02 GitHub 
repository. Load it manually or place it in the same directory as 
your CHIP-8 games.

The Studio II firmware contains five games: `A1` Doodle, `A2` Patterns, `A3` Bowling, `A4` Freeway, and `A5` Addition. Play instructions for these and more are in [docs/how-to-play.md](docs/how-to-play.md).

## Keypad and CLEAR

The keyboard is mapped like this:

```text
   Keypad A (left)        Keypad B (right)
    1  2  3                7  8  9
    Q  W  E                U  I  O
    A  S  D                J  K  L
       X                      ,
```

| Key | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|
| Keypad A | `1` | `2` | `3` | `Q` | `W` | `E` | `A` | `S` | `D` | `X` |
| Keypad B | `7` | `8` | `9` | `U` | `I` | `O` | `J` | `K` | `L` | `,` |

For CHIP-8, virtual keys `0`–`9` use keypad A `0`–`9`, while `A`–`F` use
keypad B `1`–`6` (keyboard `7`, `8`, `9`, `U`, `I`, `O`). The automatic
gamepad profile maps D-pad up/left/down/right to CHIP-8 `5/7/8/9`, Start to
`1`, Fire to `F`, and Extra to `0`. Programs choose their own layouts, so
keyboard input, direct keypad bindings, manual profiles, and Numstick remain
available when a program uses something else.

The interpreter targets classic Studio-family CHIP-8 with program space
`$0200`–`$0AFF` and about `$A0` bytes of writable game RAM at virtual
`$0B00`–`$0B9F`, backed by physical `$0800`–`$089F`. Anything fancy
or more complicated than a regular .ch8 file probably won't work.

CHIP-8 on Visicom is not supported; there is not currently a CHIP-8 interpreter 
for the platform.

**Sound: Off** silences the output without stopping or resetting the selected machine's
tone generator. Turning sound back on resumes the live beeper or tone state.

**NE555 pitch** is available on the Studio II and Visicom. Original is the
default and follows the December 1976 RCA demonstration unit at approximately
625 Hz fresh and 502.4--502.5 Hz sustained. High/Higher/Highest and
Low/Lower/Lowest retain the same pitch curve, timing, release, and retrigger
behavior while scaling the complete curve upward or downward by one, three, or
six cumulative tuning steps. The option is disabled for both Studio III
variants, which use the programmable tone path instead.

**NTSC tone pitch** is available only on the Studio III NTSC. Original uses the
native CDP1863 pitch, four times the Studio III PAL pitch for the same tone
latch. PAL (lower) selects the CDP1864 divide-by-four stage so NTSC software
plays at the PAL pitch. Changing the setting does not restart the tone generator.

**Vertical Crop: 216p (5x)** is available when the HDMI scaler output is
1920x1080 and the scandoubler is off. It crops the presented raster to 216 lines,
allowing the integer scale modes to use an exact 5x vertical scale. **Crop
Offset** moves that window up or down.

**Borders: Off** presents only the 64x128 NTSC-family bitmap or the 64x192
Studio III PAL bitmap. Only blanking is changed to allow analog out to retain 
sync and timing.

## Controller profiles

**Mapping: Auto** selects a profile from the exact cartridge file's CRC, falls back to 8-way when there is no match, and changes profile after a resident game is selected. **Manual** lets you select a profile directly. Keyboard input, direct `A0`–`B9` bindings, CLEAR, and the on-screen keypad remain available in either mode.

Gamepad 0 gets the controls for the title's primary one-player game or mode. That may be keypad A, keypad B (as in Squash), or a combination of both used by one player.

Use **Mapping: Manual** when a title has no verified profile or needs different controls.

## Numstick (On-screen keypad)

**Numstick** assigns the numstick overlay to A or B. The right stick selects 1–9, the left stick selects 0, and holding a direction for about half a second registers it. Nudge and release the right stick for 5.

## Project information

Original core by Jason Coombes, with MiSTer integration and early Pixie work by Flandango and later contributions by Alan Steremberg and Elle Ball. See the [full credits](CREDITS.md) for detailed acknowledgements. GPL-2.0-or-later; see file headers and [LICENSE](LICENSE).
