# Roadmap

Developement is effectively done. Ideas for potential improvements are listed.

## Keyboard and keypad ideas

- physical numpad support.
- Emma 02-style two-player layout: player one uses the keyboard
  number row and player two uses the physical numpad
- Retain current keyboard layout on keypad A while physical 
  numpad drives keypad B
- Add conventional CHIP-8 QWERTY layout:

  | Original CHIP-8 keypad | Standard QWERTY mapping |
  |---|---|
  | 1 2 3 C | 1 2 3 4 |
  | 4 5 6 D | Q W E R |
  | 7 8 9 E | A S D F |
  | A 0 B F | Z X C V |

- Add an optional literal CHIP-8 keyboard layout in which every COSMAC VIP
  keypad symbol uses its matching MiSTer keyboard key (A to A, B to B,
  and so on).

## Hardware and presentation

- Acquire reference audio for Studio III to verify accuracy
- Verify direct video
- Make Studio III homebrew that exercises tone generator

### Numstick refinements

- Prevent the left analog stick from also generating ordinary profile movement
  while Numstick is using it to select 0. Prefer automatic suppression while
  Numstick is active, unless an explicit left-stick option proves necessary.

  This seems difficult to do, but might be possible. Low priority.

## Deferred

High-page diagnostic ST2 images remain outside the 4 KB cartridge model. Do not
expand the loader without a concrete compatibility requirement and explicit
banking design.

### Original-era CHIP-8 compatibility

Maintain the [early CHIP-8 compatibility ledger](docs/os2-early-chip8.md), including
the owner's hardware results, blocking instructions,
and Marcel interpreter comparisons. Before redesigning OpenStudio2, account for
native 1802 calls, original memory/register and display/interrupt conventions,
and historical decoder behavior. Keep deliberate gaps documented. A future VIP
core should treat these original programs as first-class compatibility cases,
using their intended interpreter and exact images. Complete the native-call
inventories and retest Dot-Dash on hardware with OS2's comparison decoder fix.
Do not count picture-only hybrids as interpreter blockers when a standard
CHIP-8 conversion already exists. `Snoopy Cosmac picture.ch8` is covered by the
portable 296-byte `Snoopy picture [Marco Varesio, 2015].ch8` and needs no
OpenStudio2 native-call work.

- Correct CHIP-8 `Fx0A` to produce one result per physical press/release cycle.
  Physical Clock Program testing proves the current level-sensitive behavior is
  not usable for consecutive waits: one press, however brief, fills every time
  digit reached before release. Marcel's interpreter captures a press and returns
  it after release, which is the required compatibility behavior for this title.
  Scope the correction to CHIP-8 operation, preferably in firmware. Do not
  globally one-shot keypad levels in RTL: native Studio software can legitimately
  depend on a held key.
