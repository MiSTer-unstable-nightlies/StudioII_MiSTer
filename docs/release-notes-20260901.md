# 2026-09-01 controller and beeper completion

This milestone closes the controller/input and Studio II beeper projects. Both
are accepted complete rather than retained as open-ended fidelity work.

## Controller and keypad experience

The finished input model combines exact-image and resident-game controller
profiles with Auto/Manual mapping, Auto/1/2-player selection, direct access to
both physical keypads, and assignable Numstick control. Known titles receive a
useful gamepad layout while unverified controls remain available through the
manual paths instead of being guessed.

## Studio II beeper

The hardware-derived beeper preserves one continuous oscillator through its
contour, envelope, audible release, retrigger behavior, and approximately 11:6
duty ratio. Original retains the accepted RCA demonstration-unit tuning.
Low/High provide modest adjacent choices, Lower/Higher cover the broader
expected console range, and Lowest/Highest provide deliberately pronounced but
still useful alternatives. Tuning scales only the complete oscillator period.

The seven endpoint, waveform, release, and retrigger checks pass, as do RTL lint
and the headless build. Maintainer hardware listening accepted the complete
tuning range as useful and enjoyable.

## Result

Controller automapping, player-aware routing, Numstick, and the fitted beeper
form a distinctive Studio II experience rather than isolated convenience
features. No comparison is claimed against implementations that have not been
available for review, but this combination is not present in the other public
Studio II emulators reviewed during development.
