# Studio II beeper

This file records the accepted behavioral model, its evidence, and verification
boundary. Release chronology belongs in release notes and Git.

## Behavioral baseline

- The retail-reference contour has a fresh-note pitch near 628.4 Hz and a
  sustained floor near 505.2 Hz. Console tolerance is expected.
- Original, the default, scales that complete contour by approximately `0.9945`
  to the December 1976 RCA demonstration unit: about 625 Hz fresh and
  502.4--502.5 Hz sustained. Low/High, Lower/Higher, and Lowest/Highest apply
  one, three, and six cumulative reciprocal `31:32` frequency steps away from
  Original. The outer choices span approximately 516.5/415.3 Hz to
  756.1/607.8 Hz.
- Q high holds the upper pitch for about 20 ms, then follows a rounded descent
  that settles in roughly 210--220 ms.
- Q low does not mute or reset the oscillator. Pitch recovers upward continuously
  while an RC-like amplitude envelope fades over roughly 96 ms.
- Pitch and amplitude remain continuous across close Q transitions. Retriggers
  recover according to the low-gap duration and do not stack independent notes.
- FLiP's controlled Q-Sound Test gives steady retrigger crests at about 94.9%,
  97.0%, 98.7%, and 99.3% of fresh pitch for its 30, 50, 80, and 100 delay
  settings. The corresponding recorded low gaps are approximately 60.2, 105.5,
  160.7, and 205.9 ms. The supplied `S2-100-*` series, with the 50 and 100
  settings repeated at length 150, constrains the curve through 99.3%; the last
  approach to the fresh-pitch asymptote remains a monotonic continuation.
- Rapid pulses such as Speedway remain near the upper pitch. Concentration /
  Match and Gunfighter exercise close-retrigger behavior.
- The output waveform uses an approximately 11:6 high/low duty ratio while
  preserving the full-cycle period.

The December 1976 demonstration recordings independently show the same pitch
span and driven-curve family at about `0.9945` of the accepted absolute tuning.
That proportional agreement and Paul Robson's approximately 625 Hz circuit
description make the demonstration unit the Original/default reference.

## Circuit description

Paul Robson's archived Studio II technical note describes a Q-gated NE555
astable switched by the 1802's SEQ and REQ instructions. It gives `Ra = 400
kOhm` and `Rb = 480 kOhm`, with the control pin connected to ground through a
`10 uF` electrolytic capacitor. That independently supports the observed
continuous downward pitch warp and gives high/low phase lengths proportional
to `(Ra + Rb):Rb = 880:480 = 11:6`, matching the accepted duty ratio.
Read in audible units, its stated working frequency of about 625 agrees with
the measured 628.4 Hz fresh-note pitch to within about 0.5 percent.

The surviving note prints `C = 1.8 pF`, `625 kHz`, and an approximate decay to
half frequency in 0.4 seconds. The capacitance/frequency units are inconsistent
with an audible beeper and should be treated as a likely notation or
transcription error, not silently corrected. The broad description corroborates
the circuit topology and direction of the pitch change; measured gameplay audio
remains the authority for the accepted 628.4--505.2 Hz contour and timing.

Robson also describes a possible capacitor-charging circuit that extends the
first power-up beep beyond its programmed 80 ms. Treat that startup event as a
separate initial-condition problem rather than using it to tune ordinary
in-game Q pulses.

The surviving source was preserved from
`https://archive.kontek.net/studio2.classicgaming.gamespy.com/techinfo.htm`.

## Implementation

`rtl/rcastudioii.sv` maintains one oscillator state through drive, release, and
retrigger. Audible release and recovered next-start state are represented
separately: the live pitch follows the release tail, while a hidden divider
tracks recovery. On Q rising, live pitch glides to the recovered state without a
discontinuous audible edge, then rejoins the driven contour. Once the release
has become silent, the stopped oscillator follows the recovered divider so a
long-gap retrigger cannot expose a stale fresh-pitch interval during its attack.

The selected tuning scales the complete oscillator period while the drive,
release, retrigger, and amplitude timings remain unchanged. The scale is latched
with the period so its high and low phases cannot use different settings. Those
phases are then derived in an 11:6 ratio whose sum preserves the tuned full
period. The fractional-period accumulator advances once per full cycle.

The OSD uses a three-bit tuning field on Studio II and Visicom. Codes 0--6 are
Original, High, Higher, Highest, Lowest, Lower, and Low so traversing the menu
remains monotonic across its wrap; unused code 7 falls back to Original. The
setting affects only the Studio II/Visicom NE555 path. The signed sample path
remains independent of the Studio III programmable-tone path.

`Studio-II.sv` implements `Sound: On/Off` by gating `AUDIO_L` and `AUDIO_R` to
signed zero. It does not gate Q, reset either generator, or alter oscillator,
pitch, phase, or envelope state.

## Evidence and verification

The model is constrained by labeled retail-console recordings, the RCA
demonstration archive, FLiP's configurable Q-Sound Test ROM and recordings,
ROM/simulator Q cadence, and MiSTer listening. Acoustic analysis uses cycle
periods, narrow-band phase, spectral ridges, and harmonics; recordings do not
provide direct electrical Q or control-voltage timing. Controlled Q-Sound Test
measurements take precedence over earlier retrigger estimates inferred from game
cadence.

`tools/beeper-curve-test.py` checks all seven tuning endpoints, reserved-code
fallback, descent, release, retrigger families, phase-length sums, duty ratio,
and protected game cases.
`tools/verify-beeper.sh` runs the focused audio checks. Synthesis reports must
still be inspected separately for timing and inference, and MiSTer listening is
required for release acceptance.

## Accepted boundary

The Studio II beeper model and its seven tuning choices are complete. Original
is the hardware-derived reference; Low/High provide a modest adjacent choice,
Lower/Higher retain the broader expected console range, and Lowest/Highest add
deliberately pronounced but still useful alternatives. Every choice preserves
the same contour, envelope, release, retrigger behavior, duty ratio, and live
generator state.

No beeper refinement is planned. Reconsider the accepted model only if materially
better hardware evidence demonstrates an aggregate error without requiring a
title-specific path or regressing the protected rapid, long-note, release, and
close-retrigger cases.
