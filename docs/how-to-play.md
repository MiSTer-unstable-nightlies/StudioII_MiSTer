# Master how-to-play and control reference

This is the canonical gameplay and keypad reference for the RCA Studio II, Studio III / MPT-02 and Visicom COM-100 software supported by this core. It is intended both for players and as evidence for future CRC-based controller profiles.

Game names follow the Fullset v12.1 filenames. Instructions are consolidated from original manuals, author readmes, Andrew Modla's emulator notes and Emma 02 help. Original manuals and author documentation take precedence when sources disagree. Unknown controls are identified as gaps rather than guessed.

## Contents

- [Console keypad notation](#console-keypad-notation)
- [CHIP-8 programs](#chip-8-programs)
- [Profile-oriented quick index](#profile-oriented-quick-index)
- [RCA Studio II resident games](#rca-studio-ii-resident-games)
- [Studio II retail cartridges](#studio-ii-retail-cartridges)
- [Studio III / MPT-02 programs](#studio-iii--mpt-02-programs)
- [Studio II non-retail and homebrew software](#studio-ii-non-retail-and-homebrew-software)
- [Visicom COM-100](#visicom-com-100)
- [Known instruction gaps](#known-instruction-gaps)
- [Source notes](#source-notes)

## Console keypad notation

The machines have two ten-key pads, identified here as **A** and **B**. `A5` means key 5 on keypad A; `B0` means key 0 on keypad B.

```text
1 2 3
4 5 6
7 8 9
  0
```

Many games treat `2/4/6/8` as up/left/right/down and `1/3/7/9` as diagonals. This document names the console keys directly; references to PC arrow keys, Space, Tab, W/A/S/Z or a numeric keypad in emulator documentation have been translated back to A/B keypad positions where the relationship is known.

`CLEAR` means the console CLEAR button, available from F3, the OSD or gamepad Select in this core. Unless an entry says otherwise, press CLEAR before selecting or restarting a program.

## CHIP-8 programs

Download [Marcel van Tongeren's interpreter](https://www.emma02.hobby-site.com/studio_chip8.html),
and name its 768-byte image `chip8.bin`. **Load CHIP-8** automatically sends an
interpreter found beside the selected program. You can instead use **Load
CHIP-8 Interpreter** once per core session; the cached copy then serves `.ch8`
programs in any directory. Loading the interpreter alone leaves the native
machine active, and the next **Load CHIP-8** selection enters CHIP-8 mode.
Virtual CHIP-8 keys `0`–`9` map to keypad A
`0`–`9`; `A`–`F` map to keypad B `1`–`6`. Their keyboard equivalents are:

```text
CHIP-8: 0 1 2 3 4 5 6 7 8 9  A B C D E F
Key:    X 1 2 3 Q W E A S D  7 8 9 U I O
```

There is no universal gamepad layout for CHIP-8 software. Use the keyboard,
direct A/B keypad bindings, Numstick, or select a manual profile appropriate to
the game. The automatic CHIP-8 profile maps D-pad up/left/down/right to virtual
keys `5/7/8/9`, Start to `1`, Fire to `F`, and Extra to `0`.
The loader supports the classic Studio-family interpreter only;
CHIP-8X, Super-Chip, XO-CHIP, file offsets from `$900` onward, and Visicom are
not supported. The `$900`-byte payload limit follows from loading at virtual
`$0200` and requiring the program to end by `$0AFF`; it is not an `$0B00`-byte
file-size allowance.

## Profile-oriented quick index

This table records the minimum input shape needed for a useful controller profile. Full setup and play instructions follow.

| Game or program | Machine | Start / selection | Input shape |
|---|---|---|---|
| Classic CHIP-8 programs | Studio II / III | Load `.ch8` directly | D-pad `5/7/8/9`; Start `1`; Fire `F`; Extra `0` |
| Resident Doodle / Patterns | Studio II | `A1` / `A2` | 8-way on B plus B5/B0 |
| Resident Bowling | Studio II | `A3` | Cross plus center, alternating A/B |
| Resident Freeway | Studio II | `A4`, then B0/A0 | B4/B6 steer; A2 accelerates; A8 brakes |
| Resident Addition | Studio II | `A5` | Full numeric keypad |
| Baseball | Studio II / Visicom | `A0` | A/B cross plus center; roles swap |
| Biorhythm | Studio II | `A0` | Full numeric keypad B |
| Blackjack | Studio II | `A1` or `A2` | Full numeric keypads; 1/2/0 actions |
| Concentration + Match | Studio III / MPT-02 | Any digit chooses a player | Full numeric A/B |
| Fun with Numbers | Studio II | `A1`, `A2` or `A3` | Full numeric A/B |
| Gunfighter / Moonship Battle | Studio II | `A1`, `A2` or `A3` | Cross/8-way plus center on A/B |
| Pinball | Studio III / MPT-02 | `A1` or `A2` | 4/6 flippers, 1 launch, 0 shove |
| Space War | Studio II | `A1` or `A3` | Asymmetric A/B fire and steering |
| Speedway / Tag | Studio II | `A1` or `A2` | Cross on both pads |
| Star Wars | Studio III / MPT-02 | `A1`, `A2` or `A3` | Cross on both pads; role inversion |
| Tennis / Squash | Studio II | `A2` / `A1` | 2/8 paddles plus setup digits |
| TV Bingo | Studio III / MPT-02 | `A1`–`A4` | Full numeric B |
| Asteroids | Studio II | `A5` | 2/4/6 plus 0; either pad |
| Berzerk | Studio II | `A5` | 8-way A, fire B0 |
| Fifteen Puzzle | Studio II | any A key | Cross plus center on A |
| Combat | Studio II | game code on A, then B0 | Cross plus fire on both pads |
| Hockey | Studio II | `A1`–`A4`, then `A8/A9` | 2/8/0 on both pads |
| Invaders | Studio II | `A0` restarts | A4/A6 movement, B0 fire |
| Invasion, The | Studio II | `A1`–`A6` difficulty | A4/A6 movement, A5 fire |
| Flappy Pixel | Studio II | not yet documented | A5 flap; existing 8-way profile fits |
| Kaboom | Studio II | `A0` | A4/A6 movement |
| Pacman | Studio II | `A0` | A2/A4/A6 and B8 |
| Race | Studio II / Visicom | not yet documented | 8-way A; A2 acceleration can be held while steering |
| Scramble | Studio II | `A6` or `B6` | 2/4/8/0; either pad |
| Space Explorer | Studio II | program starts directly | 8-way B, B5 lock, A0 fire |
| Visicom resident games | Visicom | `A1/A2/A3/A4/A7` | Varies; mostly cross/full keypad |
| Visicom cartridges | Visicom | normally `A0` | Per-title; several remain unknown |

## RCA Studio II resident games

The standard Studio II firmware contains five selectable programs.

### Doodle — `A1`

- Move the dot with the eight direction keys on keypad B.
- `B5` draws; `B0` moves without drawing. Retracing a line erases it.
- Doodle can be handed into Patterns by pressing `A2`. Press a direction, then `B0`, to begin transforming the image; `B5` freezes and `B0` resumes.

### Patterns — `A2`

- The screen remains dark until movement is entered on keypad B.
- Enter a path with the eight direction keys. Retrace to erase.
- `B0` starts the repeating pattern before the 130-move memory is full; otherwise repetition begins automatically at 130 moves.
- `B5` freezes the pattern and `B0` resumes it.

### Bowling — `A3`

- Players alternate, first using keypad A and then keypad B.
- `2` hooks upward/left, `5` rolls straight and `8` hooks downward/right.
- The game lasts ten frames. A strike is displayed as `ST-20`, a spare as `SP-15`.

### Freeway — `A4`

- `B0` starts the normal game; `A0` starts the difficult game.
- `A2` accelerates, `A8` brakes, and `B4/B6` steer left/right.
- Avoid the computer car. Distance is scored after two minutes.

### Addition — `A5`

- Add the three displayed digits and enter the total on either keypad.
- Faster correct answers score more, up to 11 points per problem. A wrong answer locks that player out for the current problem.
- The game lasts 20 problems.

## Studio II retail cartridges

### TV Arcade I - Space War

Press CLEAR before selecting a game.

**Horizontal Intercept — `A1`**

- `A2` fires a rocket.
- `B4/B6` steer it left/right.
- Twenty rockets are available; rockets remaining appear at lower left and score at lower right.

**Vertical Intercept — `A3`**

- `A2` launches the left missile and `B2` launches the right missile.
- Holding the key keeps a missile straighter; releasing it makes the trajectory angle downward.
- Each hit scores 10 and reverses the central ship. The game ends after it reaches the top marker eight times.

### TV Arcade II - Fun with Numbers

- `A1`: Guess the Number, one player. Player uses keypad B.
- `A2`: Guess the Number, two players. Each player first enters a secret three-digit number.
- `A3`: Reverse.

In Guess the Number, enter guesses on the active keypad. The three-digit clue counts correct digits and positions: `000` means none correct and `006` means the number is solved. Intermediate totals combine correctly placed and misplaced digits. Digits may repeat and zero is valid.

The one-player Guess the Number game allows 20 guesses. In Reverse, reorder 1–9 in no more than 30 moves by pressing `B2`–`B9`; the digit says how many leading positions to reverse.

### TV Arcade III - Tennis + Squash

- `A1`: Squash, one player using keypad B.
- `A2`: Tennis, two players using both keypads.
- Each player chooses racquet size on their pad: `4` small, `5` medium, `6` large.
- Player A selects ball speed and begins: `A7` slow, `A8` normal, `A9` fast.
- During play, `2` moves a racquet up and `8` down on its player's keypad. Between serves, `0` pauses/resumes.
- The `Tennis` controller profile starts `A1` Squash in Auto/1P and drives
  keypad B from controller 1. With Players set to 2, Start selects `A2` Tennis
  and controllers 1/2 drive keypads A/B. Extra supplies each player's `0`
  pause key.
- Tennis is first to 21, winning by two. Squash ends after 21 misses or 200 completed volleys.

### TV Arcade IV - Baseball

- Press `A0`. Keypad A bats first and keypad B pitches/fields; roles swap every half-inning.
- Batter: `5` swings.
- Pitcher: `2` inside curve, `5` straight, `8` outside curve. Hold about a quarter-second for a change-up.
- Fielders: `2` up and `8` down.
- The lower-left result is `F` foul, `1/2/3` base hit, `H` home run, `W` walk or `O` out.
- The game lasts nine innings. Ties continue into extra innings, up to 99 innings or until a player reaches 99 runs.

### TV Arcade Series - Gunfighter + Moonship Battle

**Gunfighter**

- `A1`: one player, using keypad B. `A2`: two players.
- Each player uses `2/8` to move up/down and `5` to fire.
- Tap `5` for one fast bullet; hold it for two slower bullets.
- Two minutes; most hits wins.

**Moonship Battle — `A3`**

- Each player moves in eight directions on their own keypad and fires with `5`.
- Rockets travel in the last movement direction.
- Each ship begins with 100 energy. Movement, firing, hits and collisions consume energy; the first ship depleted loses.

### TV Arcade Series - Speedway + Tag

- `A1`: Speedway. `A2`: Tag.
- Both players move with `2/4/6/8` on their own keypads.
- Speedway is a nine-lap race; wall and car impacts slow the player.
- Tag awards 10 points per tag. The role changes after a tag or about ten seconds. Highest score after two minutes wins, or first to 300.

### Star Wars

- `A1`: one player. `A2`: two players. `A3`: advanced one player.
- At `SPEED 1 2 3?`, choose `1` slow, `2` medium or `3` fast. In two-player mode, the keypad used for this choice starts as the chaser.
- Both players use `2/4/6/8` on their own pad.
- When chased, the keys move normally. When pursuing as the viewfinder, directions invert: `2` moves the target down, `8` up, `4` right and `6` left.
- First to nine destroyed ships wins.

### TV Casino Series - Blackjack

- `A1`: one player, using keypad B. `A2`: two players.
- At `CUT`, press `0`. At `BET`, press `1`–`9` for $1–$9 or `0` for $10.
- During play: `1` hit, `2` double and `0` stand on the active player's keypad.
- Dealer draws on 16 or less and on soft 17. Blackjack pays 2:1; an ordinary win pays 1:1.

### TV Casino Series - TV Bingo

- `A1`: manual calling; press `A1` for each new number.
- `A2`: automatic calling every 12 seconds; `A0` stops or `A1` returns to manual.
- `A3`: verify mode. Enter a claimed winning card on keypad B; `OK` means a number was called and `NO` means it was not.
- In verify mode, enter the five claimed numbers as two digits each and omit the free space. When all five show `OK`, press `A0` to display their point total and play the tune; `A3` restarts an incorrectly entered verification.
- `A4`: play the bingo tune.

### TV Mystic Series - Biorhythm

- Press `A0`.
- Enter birth date and then chart start date on keypad B in `MM DD YYYY` form.
- The 32-day chart labels physical (`P`), emotional (`E`) and intellectual (`I`) cycles and marks seven-day intervals.

### TV School House I

- `A1`: fast response, about 10 seconds. `A2`: slow response, about 20 seconds.
- Choose quiz 1–9 and use the matching printed quiz booklet. The displayed letter A–H identifies the question.
- A solo player may answer on either keypad. With two players, each uses their own keypad and races to answer first.
- A wrong answer locks that player out for the current question. Correct answers score 1–10 points depending on speed; the quiz ends after 12 questions.

### TV School House II - Math Fun

- `A1`: slow response, about 20 seconds. `A2`: fast response, about 10 seconds.
- Choose `1` addition, `2` subtraction, `3` multiplication, `4` division or `5` combination.
- For the first four types, then choose difficulty 1–4.
- A solo player may answer on either keypad. With two players, each uses their own keypad and races to answer first.
- Correct answers score 1–10 points depending on speed; a wrong answer locks that player out for the problem. The game lasts ten problems.
- After the final score, `A0` repeats the same setup; CLEAR returns to setup selection.

### Concentration + Match

- Either player starts by pressing a digit on their own keypad. The first pad used becomes the first player.
- The starting digit controls how long symbols are exposed: `0` shows none; `9` shows them longest.
- During play, keypad A positions `1`–`9` select the nine cards on the left and keypad B positions `1`–`9` select the nine on the right.
- A match scores one point and keeps the turn; a miss passes it. After all nine pairs are found, a new layout begins with the other player. First to 25 points wins.

### Pinball

- `A1`: one player, using keypad B. `A2`: two players, alternating pads.
- On the active pad, `1` puts a ball in play, `4/6` operate the left/right flippers and `0` reverses the ball to simulate shoving the cabinet.
- Bumpers change randomly between values 2–9. Repeated use of `0` causes TILT. Each player receives five balls; a score above 999 ends the game.

## Studio III / MPT-02 programs

Studio II-compatible cartridges above also run on several MPT-02-family machines. Their physical joystick commonly maps the cross to `2/4/6/8`, fire to `5` and the extra button to `0`.

### Grand Pack

- `A1` Doodle, `A2` Patterns, `A3` Bowling, `A4` Blackjack one-player and `A5` Blackjack two-player.
- Doodle and Patterns use the resident-game movement and drawing controls above. Their keypad A colour/tone choices are `3` red/do, `4` blue/re, `5` violet/mi, `6` green/fa, `7` yellow/sol, `8` light blue/la, `9` white/si and `0` black/do.
- Patterns stores up to 128 entries; a colour/tone change uses three entries. `B0` begins or resumes repetition and `B5` freezes it.
- Bowling follows the resident controls and lasts ten frames; a strike scores 20, a spare 15 and a perfect game 200.
- In Blackjack, players can bet $01–$99; active-pad actions are `1` hit, `2` double and `0` stand.

The merged Grand Pack and its two split dumps represent the same package and should share mapping research.

## Studio II non-retail and homebrew software

### Game Pack (Doodle, Curling, Pong, Addition, Freeway)

- `A1` Doodle: directional movement; `B5` draws and `A0/B0` erases.
- `A2` Curling: the active player holds `0` long enough to reach a target symbol.
- `A5` Pong variant: hold `0` to push the paddle upward; releasing returns it downward.
- `A6` Addition: enter the displayed sum; quicker answers score more.
- `A7` Freeway: `A5` starts/accelerates and `A4/A6` steer.

### A Cheap Graphics Computer

Do not press CLEAR while changing modes; it destroys program data. Use `B0` to return to mode selection and save most CPU registers into RAM.

- `A1` Load: enter a four-hex-digit address, then program bytes. Digits 0–9 use keypad A; hexadecimal A–F use `B1`–`B6`.
- `A2` Memory Read: enter an address, then press any A digit to step through memory.
- `A3` Run: enter the four-digit start address. Execution begins from R9.
- `A4` Shift: enter an address, then `A8` shifts page `$0800` or `A9` shifts page `$0900` upward by one byte.

Normal program space starts at `$0800`; bitmap RAM is `$0900-$09FF` and can be reused when a full display is unnecessary.

### Asteroids

- `A5` starts each level.
- Either keypad: `2` thrust/move, `4/6` rotate left/right and `0` fires.

### Berzerk

- `A5` starts each level.
- Keypad A `1/2/3/4/6/7/8/9` moves in eight directions.
- `B0` fires in the current walking direction.

### Climber v1.00

- `A3` novice, `A4` standard, `A5` advanced, `A6` expert.
- Move with `A2` up and `A4/A6` left/right.
- After game over, `B1` plays again; CLEAR generates a fresh start.

### Fifteen Puzzle

- After CLEAR, press any key on keypad A. The game generates a new 4x4 puzzle; the progress bar shows generation status.
- `A2/A4/A6/A8` move the white cursor and `A5` slides the highlighted piece into the adjacent empty space.
- Arrange 1–15 (shown as 1–9 and A–F) from left to right, top to bottom, with the empty space at bottom right.
- Only orthogonally adjacent pieces can move. Press CLEAR for a newly generated puzzle.

### Combat v1 / v2 / v3

- At `G?`, enter a decimal game code on keypad A, then press `B0` to begin.
- Each player uses `4/6` to turn, `2/8` for forward/backward (or plane speed) and `0` to fire on their own pad.
- First to nine hits wins; collisions are fatal.

Game code is a bit sum: add 128 for plane, 64 for long-range missiles, 32 for slow missiles, 16 for an enclosed area, 8 for tank bases, 4 for full terrain, 2 for balloons or 1 for mines. The last four terrain additions are mutually exclusive. For example, `0` is tank/short/fast with an open field; `209` is plane/long/fast/enclosed with mines; `248` is plane/long/slow/enclosed with tank bases.

### Hockey v1 / v2 / v3

- First select `A1` Hockey, `A2` Soccer/doubles tennis, `A3` Pong or `A4` Squash.
- Then press `A8` for easy or `A9` for hard.
- Each player's pad uses `2/8` for up/down and `0` to serve.

### Invaders v1 / v2 / v3

- `A4/A6` move left/right, `B0` fires and `A0` restarts.
- The game has four rows of eight invaders and no mothership.

### Invasion, The v1.00

- After CLEAR, select difficulty with `A1` easiest through `A6` hardest.
- `A4/A6` move the laser cannon left/right and `A5` fires.
- Only one missile can be active. Regular missiles disappear on impact; indestructible missiles must leave the screen before another shot can be fired.
- A hit scores one point; the score rolls over after 255. The player begins with three lives. Difficulty increases every eight waves.

### Flappy Pixel

- `A5` flaps. The existing 8-way profile maps Fire to `A5` and therefore
  supplies the documented play control.

### Kaboom

- `A0` starts.
- `A4/A6` move left/right.

### Pacman

- `A0` starts.
- `A2` up, `A4` left, `A6` right and **`B8` down**.
- Inputs request the next direction rather than continuously forcing movement. Losing a life refills the maze; there is no bonus life.

### Scramble

- At `G?`, press `2` easy, `4` medium or `6` hard.
- `A6` or `B6` starts each level.
- Either pad: `2` up, `8` down, `4` brake and `0` fire. Firing while braking drops a bomb; otherwise it launches a missile.
- Destroy fuel dumps periodically to refuel.

### Outbreak v1.00

- `A0` novice, `A1` standard, `A2` advanced, `A3` expert.
- `A4/A6` move the reflector. Hold the corresponding `B4/B6` simultaneously for double speed.
- After game over, `B1` plays again; CLEAR begins a fresh game.

### Race

- Move in eight directions on keypad A.
- `A2` accelerates and may be held together with a direction key. The automatic
  profile maps acceleration to Fire independently so steering remains available.
- Physical-keypad handling of every `A2`-plus-direction chord is not yet verified.

### Rocket v1.01

- `A1` starts and `A5` fires.
- After nine rockets, press CLEAR to restart.

### Space Explorer

- Move the central cursor over a target with keypad B's eight direction keys.
- `B5` locks onto the target; `A0` fires.
- Eliminate all nine dots before the timer expires. The objective is a low score; taking longer to destroy a target reduces it.

### TV Arcade 2012 v1.00

- `A1` Craps: bet with 1–9. On a point, press a nonzero key to reroll until making the point or rolling seven.
- `A2` Moon Lander: each turn enter 0–9 fuel. Land with final downward velocity no greater than 5.
- `A3` Repeat After Me: reproduce the sequence using 1–4; 25 correct digits is perfect.
- `A4` Space Rescue: steer left/right with `A4/A6` and avoid asteroids.
- `A5` Nim 1, last stone loses. `A6` Nim 2, last stone wins. Players remove 1–3 stones on their own pad; `0` resets game and scores.

### Test and demonstration images

- **RCA Test Cartridge - Tester 1** is a 1976 diagnostic by Jack Wright; no player instructions are documented in the supplied notes.
- **Demonstration Cartridge** is Andrew Modla's 1977 point-of-sale demonstration and is not documented as an interactive game.
- The supplied **Studio III Point of Sale Demonstration** note says the original program is unavailable and a Studio II image was substituted.
- The Joseph Weisbecker programming examples and other diagnostic/demo images need direct probing before controller profiles are assigned.

## Visicom COM-100

Select the Visicom machine and use its firmware. Visicom cartridges normally enter from `A0`; their internal game-selection keys are listed separately below.

### Resident games

| Game | Select | Controls |
|---|---|---|
| Doodle | `A1` | Eight-direction movement on A draws immediately. `A0` cycles red → dark green/erase → blue → green; `A5` cycles backward. |
| Bowling | `A2` | Players alternate; `2` hook up, `5` straight, `8` hook down on the active pad. |
| Patterns | `A3` | Draw as in Doodle, then press `A3` again to repeat the pattern. |
| Freeway | `A4` | `A5` starts; `A2/A8` accelerate/brake and `A4/A6` steer. Two-minute score. |
| Addition | `A7` | Add the displayed digits and enter the total; player 1 uses A and player 2 B. Twenty problems. |

### Sports Fan (Baseball & Sumo Wrestling) (CAS-130)

The cartridge enters on `A0`.

**Baseball** uses the same role-swapping controls as Studio II Baseball: active-pad `5` swings/throws straight, `2/8` select curves and move fielders, and holding a pitch produces a change-up.

**Sumo Wrestling**

- `A5` begins the event; press `A0` and `B0` for the initial charge.
- Player A: `A6` push, `A4` pull, `A5` throw.
- Player B: `B4` push, `B6` pull, `B5` throw.

### Inspiration (Fortunetelling & Biorhythm) (CAS-190)

The cartridge enters on `A0`. Keypad A controls editing: `A5` accepts/enters and `A0` deletes the current input. Dates and answers are entered on keypad B.

- `A5`: Bagua Fortune Telling. Enter dates as `YYYY MM DD` on B.
- `A6`: Blood Horoscope. On B, `1` blood type A, `2` B, `3` AB, `4` O.
- `A0`: Horoscope. Enter `YYYY MM DD`; where only a birthday is requested, enter `MM DD`.

### Other dumped Visicom cartridges

These enter on `A0`, but the supplied sources do not document enough post-start controls for a reliable profile:

- Arithmetic Drill (Math Fun & Fun with Numbers) (CAS-110)
- Gambler I (Blackjack) (CAS-140)
- Gambler II (Slot Machine and Dice) (CAS-141)
- Space Command (CAS-160)

Do not infer their controls merely from similarly named Studio II cartridges; verify them by manual, trace or direct play first.

## Known instruction gaps

The Fullset v12.1 also contains software for which the supplied sources give no dependable gameplay instructions. These are explicit research items for future profile work:

- Public-domain games: noshaders. Flappy Pixel and Race now have mapped play
  controls, but their complete start/restart behavior is not yet documented;
  Race's physical-keypad acceleration chords also need verification.
- Non-retail/prototype software: Baseball-2K, Basic Videomate, Biorhythm prototype, Color Demo, Color Runs, Colors Stars and Trek, Gunfight, New Studio 2-5 Game Set, Numbers, Paul's Printer, Print Snoopy, Secret Number, Space War (512 Bytes), ST3CTA Tester 3, Studio 2 Quiz, the Studio II-TV Tennis variants and Tag-Race.
- Utility/firmware images: AM4KBAS, the Studio IV interpreter images, VIP firmware and the 40th Anniversary Multi-Cart.

When filling a gap, record at minimum: exact Fullset filename and CRC, machine, initial selection sequence, A/B keypad usage, player count, every in-game action, restart/pause behavior and the source or hardware observation used.

## Source notes

- Original RCA cartridge manuals and standalone manual transcriptions supplied with the software.
- Paul Robson's author readmes for Asteroids, Berzerk, Combat, Hockey, Invaders, Kaboom, Pacman and Scramble.
- Lee Romanow's author documentation for Climber, Fifteen Puzzle, Invasion, Outbreak, Rocket and TV Arcade 2012.
- Direct project control testing for Flappy Pixel and Race.
- Andrew Modla's `rca-studio2` data notes for Pinball, Space Explorer, the test cartridge and demonstration images.
- Emma 02 how-to-play material for Studio II, MPT-02 and Visicom resident/cartridge software.
- AtariAge user etxmato's documented controls for Visicom Inspiration.

Treat this file as a control-research reference, not proof that a current automatic profile is complete. CRC mappings in RTL must still use hashes of the exact distributed files.
