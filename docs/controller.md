# Controller implementation

Game controls belong in [how-to-play.md](how-to-play.md), user-facing options in
[Readme.md](../Readme.md), and unfinished work in [roadmap.md](../roadmap.md#controller-and-keypad-refinements).

## Hardware and input paths

Studio II scans two ten-key pads through a CD4515 decoder. `OUT 2` latches the
low four data bits as the digit selection; EF3 reads keypad A and EF4 keypad B.
Selections 10–15 have no key. CLEAR is independent of both pads.

`Studio-II.sv` supplies MiSTer joystick, keyboard, direct keypad and Numstick
inputs. `rtl/rcastudioii.sv` combines them into A/B masks for the selected digit.
Direct bindings and Numstick remain available alongside a controller profile.
The physical keyboard switches to the standard 4x4 QWERTY CHIP-8 layout only
while CHIP-8 is active; held keyboard state is cleared at that mode boundary.

`rtl/studio2_input_mapping.svh` owns identification, profile state, keypad masks
and controller routing. `rtl/studio2_cart_profiles.svh` maps cartridge CRCs to a
profile and Start key. Profile IDs match the OSD list in `Studio-II.sv`.
Automatic selection is reflected in OSD bits `[5:2]`; Manual uses the selected ID.

## Identification and state

Cartridge identification uses CRC16-CCITT over the exact downloaded bytes:
polynomial `0x1021`, initial value `0xFFFF`. Headers affect the CRC. Verify the
image, container, machine, selection sequence and controls before adding an
entry; `tools/cart-crc.sh` hashes supplied images. Unknown images use `8-way`.

Each machine retains separate cartridge and resident-firmware profile state.
Cartridge metadata also records the normal keypad for the generic 8-way layout.
Cartridge loading replaces that machine's cartridge selection. Unload reveals
its remembered resident mapping. Ordinary reset re-arms resident selection;
firmware replacement invalidates the resident selection.

Resident games use the first recognized firmware selection key after reset,
so gameplay keys cannot change the profile. Grand Pack's paged image uses the
same Studio III menu decoder without replacing resident-firmware state. Its
supported image and selection keys are documented in the gameplay reference.
CHIP-8 activation selects the common CHIP-8 profile.

## Mapping and routing

The design goal is predictable, consistent mappings based on each game's known
controls. Default/Auto should avoid blindly sending the same input to both
keypads wherever feasible: unintended keys can have unwanted effects. Send
simultaneous A/B keys only when the verified action requires them. Prefer
eight-way movement as the common baseline; profile differences chiefly concern
Start, Fire and Extra assignments, their target keypad(s), and verified special
cases such as Freeway, Visicom Bowling, Visicom Doodle/Patterns and Race.

The neutral `8-way` layout supplies all ten digits: directions select
`1/2/3/4/6/7/8/9`, Fire selects `5`, and Extra selects `0`. These positions match
the marked Visicom joystick. MPT-02 manuals explicitly document the optional
joystick adaptor's `2/4/6/8` cardinal equivalence for Speedway/Tag and Star Wars;
they do not establish a universal Fire/Extra layout for the machine family.

Profiles produce separate A/B keypad masks. Players chooses which controller
supplies those masks; asymmetric games can use both pads for one player's
actions. Start supplies the profile's selection key independently of movement.
The current routing exceptions are:

- Generic `8-way` Auto sends controller 1 to the normal keypad only: A by
  default; B for recognized Pinball, Blackjack, Fun with Numbers, Biorhythm,
  Gambler I/II images, and Studio III/Grand Pack Blackjack. Players 1 mirrors A/B;
  Players 2 splits controllers 1/2 across A/B. Start remains on A and direct
  keypad bindings remain independent. Manual `8-way` retains the detected
  game's normal keypad.
- Bowling mirrors controller 1 in Auto/1P and splits A/B in 2P.
- Gunfighter/Tennis uses B in Auto, mirrors A/B in 1P, and splits A/B in 2P.
  Start stays A1; game selection is independent of Players.
- Doodle always draws on B from controller 1.

Profiles share verified control needs. Cross-pad actions such as Space War's
A-side fire/B-side steering and Outbreak's A+B fast movement require distinct
masks. Direction restrictions and button substitutions must justify their
benefit over stock eight-way controls; the remaining audit is in the roadmap.
