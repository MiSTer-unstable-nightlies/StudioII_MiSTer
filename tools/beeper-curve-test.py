#!/usr/bin/env python3
"""Focused checks for the Studio II pitch, waveform, release, and retrigger model."""

from pathlib import Path
import math
import re


PIXEL_CLOCK = 1_760_229
RTL = Path(__file__).resolve().parents[1] / "rtl" / "rcastudioii.sv"
TEXT = RTL.read_text(encoding="utf-8")
TOP_LEVEL = RTL.parents[1] / "Studio-II.sv"
TOP_TEXT = TOP_LEVEL.read_text(encoding="utf-8")


def parameter(name: str) -> int:
    match = re.search(rf"{name}\s*=\s*\d+'d(\d+)", TEXT)
    assert match, f"could not find {name} in {RTL}"
    return int(match.group(1))


TOP = parameter("SND_HALF_TOP")
BOTTOM = parameter("SND_HALF_BOTTOM")
HOLD_TICKS = parameter("SND_HOLD_TICKS")
RELEASE_STEP = parameter("SND_RELEASE_STEP")
RETRIGGER_SETTLE = parameter("SND_RETRIGGER_SETTLE")
RETRIGGER_TRACK_STEP = parameter("SND_RETRIGGER_TRACK_STEP")
ATTACK_STEP = parameter("SND_ATTACK_STEP")
DUTY_HIGH_PARTS = parameter("SND_DUTY_HIGH_PARTS")
DUTY_PARTS = parameter("SND_DUTY_PARTS")
DUTY_ROUND = parameter("SND_DUTY_ROUND")
TUNE_HIGHEST = parameter("SND_TUNE_HIGHEST_Q14")
TUNE_HIGHER = parameter("SND_TUNE_HIGHER_Q14")
TUNE_HIGH = parameter("SND_TUNE_HIGH_Q14")
TUNE_MEDIUM = parameter("SND_TUNE_MEDIUM_Q14")
TUNE_LOW = parameter("SND_TUNE_LOW_Q14")
TUNE_LOWER = parameter("SND_TUNE_LOWER_Q14")
TUNE_LOWEST = parameter("SND_TUNE_LOWEST_Q14")
TUNE_DENOMINATOR = 1 << 14
TUNE_ROUND = 1 << 13

bands = [
    (int(limit), int(interval))
    for limit, interval in re.findall(
        r"half_period < 16'd(\d+)\) snd_decay_interval = 13'd(\d+)", TEXT
    )
]
last_interval = re.search(
    r"else\s+snd_decay_interval = 13'd(\d+)", TEXT
)
assert len(bands) >= 7 and last_interval, "could not parse decay bands"
intervals = [interval for _, interval in bands] + [int(last_interval.group(1))]

control_body = re.search(
    r"function automatic \[15:0\] snd_control_interval.*?endfunction", TEXT, re.S
)
assert control_body, "could not parse control-recovery bands"
control_bands = [
    (int(limit), int(interval))
    for limit, interval in re.findall(
        r"half_period >= 16'd(\d+)\) snd_control_interval = 16'd(\d+)",
        control_body.group(0),
    )
]
control_last = re.search(
    r"else\s+snd_control_interval = 16'd(\d+)", control_body.group(0)
)
assert control_bands and control_last, "could not parse control interval table"


def decay_interval(half_period: int) -> int:
    for limit, interval in bands:
        if half_period < limit:
            return interval
    return intervals[-1]


def control_interval(half_period: int) -> int:
    for limit, interval in control_bands:
        if half_period >= limit:
            return interval
    return int(control_last.group(1))


def release_interval(amplitude: int) -> int:
    if amplitude >= 192:
        return 170
    if amplitude >= 128:
        return 240
    if amplitude >= 64:
        return 400
    if amplitude >= 32:
        return 800
    if amplitude >= 16:
        return 1600
    if amplitude >= 8:
        return 3200
    return 5700


class Beeper:
    def __init__(self) -> None:
        self.half = TOP
        self.drive_half = TOP
        self.control_half = TOP
        self.curve = 0
        self.control_count = 0
        self.on_ticks = 0
        self.track_count = 0
        self.amp_count = 0
        self.amp = 0
        self.q_prev = False

    def tick(self, q: bool) -> None:
        previous_q = self.q_prev
        self.q_prev = q

        if q != previous_q:
            self.amp_count = 0
            if q:
                self.on_ticks = 0
                self.curve = 0
                self.track_count = 0
                self.drive_half = TOP
            else:
                self.on_ticks = 0
                self.track_count = 0
                self.control_half = self.half
                self.control_count = 0

        if not q:
            if self.half > TOP:
                if self.curve >= RELEASE_STEP - 1:
                    self.curve = 0
                    self.half -= 1
                else:
                    self.curve += 1
            else:
                self.curve = 0
            if not previous_q:
                if self.control_half > TOP:
                    if self.control_count >= control_interval(self.control_half) - 1:
                        self.control_count = 0
                        self.control_half -= 1
                    else:
                        self.control_count += 1
                else:
                    self.control_count = 0
            if self.amp:
                if not previous_q and self.amp_count >= release_interval(self.amp) - 1:
                    self.amp_count = 0
                    self.amp -= 1
                elif not previous_q:
                    self.amp_count += 1
            else:
                self.amp_count = 0
                self.half = self.control_half
            return

        if previous_q:
            self._settle_retrigger()
            if self.on_ticks < HOLD_TICKS:
                self.on_ticks += 1
                self.curve = 0
            elif self.drive_half < BOTTOM:
                if self.curve >= decay_interval(self.drive_half) - 1:
                    self.curve = 0
                    self.drive_half += 1
                    if self.drive_half - 1 >= self.half:
                        self.half = self.drive_half
                        self.control_half = self.drive_half
                        self.control_count = 0
                else:
                    self.curve += 1
            else:
                self.drive_half = BOTTOM
                if self.half < BOTTOM:
                    self.half = BOTTOM
                    self.control_half = BOTTOM
                self.curve = 0

        if previous_q and self.amp < 255:
            if self.amp_count >= ATTACK_STEP - 1:
                self.amp_count = 0
                self.amp += 1
            else:
                self.amp_count += 1
        else:
            self.amp_count = 0

    def _settle_retrigger(self) -> None:
        if self.on_ticks >= RETRIGGER_SETTLE:
            self.control_count = 0
            self.track_count = 0
            return
        if self.control_half > TOP:
            if self.control_count >= control_interval(self.control_half) - 1:
                self.control_count = 0
                self.control_half -= 1
            else:
                self.control_count += 1
        else:
            self.control_count = 0
        if self.half > self.control_half:
            if self.track_count >= RETRIGGER_TRACK_STEP - 1:
                self.track_count = 0
                self.half -= 1
            else:
                self.track_count += 1
        else:
            self.track_count = 0
        if self.on_ticks >= RETRIGGER_SETTLE - 1:
            self.track_count = 0
            self.half = self.control_half

    def run_ms(self, milliseconds: float, q: bool) -> None:
        for _ in range(round(milliseconds * PIXEL_CLOCK / 1000)):
            self.tick(q)

    @property
    def hz(self) -> float:
        if self.half == TOP:
            # The plateau alternates 1400/1401-tick half-cycles, 574/1024 long.
            return PIXEL_CLOCK / (2 * (TOP + 574 / 1024))
        # Other divider values are terminal counts, hence half+1 ticks.
        return PIXEL_CLOCK / (2 * (self.half + 1))


def check(label: str, condition: bool, detail: str) -> None:
    if not condition:
        raise AssertionError(f"{label}: {detail}")
    print(f"ok  {label}: {detail}")


def tune_scale(code: int) -> int:
    return {
        0: TUNE_MEDIUM,
        1: TUNE_HIGH,
        2: TUNE_HIGHER,
        3: TUNE_HIGHEST,
        4: TUNE_LOWEST,
        5: TUNE_LOWER,
        6: TUNE_LOW,
        7: TUNE_MEDIUM,
    }[code]


def tuned_full_ticks(base_ticks: int, tune_code: int) -> int:
    product = 2 * base_ticks * tune_scale(tune_code)
    return (product + TUNE_ROUND) // TUNE_DENOMINATOR


def phase_lengths(base_ticks: int, tune_code: int):
    full_ticks = tuned_full_ticks(base_ticks, tune_code)
    high_ticks = (full_ticks * DUTY_HIGH_PARTS + DUTY_ROUND) // DUTY_PARTS
    return high_ticks, full_ticks - high_ticks


check(
    "duty constants",
    DUTY_HIGH_PARTS == 11 and DUTY_PARTS - DUTY_HIGH_PARTS == 6,
    f"{DUTY_HIGH_PARTS}:{DUTY_PARTS - DUTY_HIGH_PARTS} high/low target",
)

check(
    "three-bit tuning selector",
    'O[19:17],NE555 pitch,Original,High,Higher,Highest,Lowest,Lower,Low' in TOP_TEXT
    and ".beeper_tune(status[19:17])" in TOP_TEXT,
    "status[19:17] exposes seven ordered tuning values",
)
check(
    "NE555 menu availability",
    re.search(
        r"\(machine_active == 2'd1\)\s*\|\|\s*"
        r"\(machine_active == 2'd2\).*?16'h0010",
        TOP_TEXT,
        re.S,
    )
    is not None,
    "Studio III PAL/NTSC hide the selector; Studio II and Visicom expose it",
)
check(
    "reserved tuning fallback",
    tune_scale(7) == TUNE_MEDIUM
    and "default: snd_tune_period_scale = SND_TUNE_MEDIUM_Q14;" in TEXT,
    "unused code 7 decodes to Original",
)
check(
    "one/three/six-step tuning scales",
    (TUNE_HIGHEST, TUNE_HIGHER, TUNE_HIGH, TUNE_MEDIUM,
     TUNE_LOW, TUNE_LOWER, TUNE_LOWEST)
    == (13617, 14978, 15960, 16475, 17006, 18121, 19932),
    "Q14 endpoints follow cumulative -6/-3/-1/0/+1/+3/+6 period steps",
)

tuning_targets = {
    "Original": (0, (624.6, 625.1), (502.2, 502.8)),
    "High": (1, (644.8, 645.4), (518.3, 519.0)),
    "Higher": (2, (687.0, 687.6), (552.4, 553.0)),
    "Highest": (3, (755.7, 756.4), (607.5, 608.2)),
    "Lowest": (4, (516.2, 516.9), (415.0, 415.7)),
    "Lower": (5, (568.0, 568.6), (456.4, 457.0)),
    "Low": (6, (605.2, 605.8), (486.5, 487.1)),
}
for tune_name, (tune_code, top_window, bottom_window) in tuning_targets.items():
    for label, base_ticks in (
        ("top short", TOP),
        ("top long", TOP + 1),
        ("bottom", BOTTOM + 1),
    ):
        high_ticks, low_ticks = phase_lengths(base_ticks, tune_code)
        full_ticks = tuned_full_ticks(base_ticks, tune_code)
        check(
            f"{tune_name} {label} phase lengths",
            high_ticks + low_ticks == full_ticks
            and abs(high_ticks - full_ticks * 11 / 17) <= 0.5,
            f"{high_ticks}+{low_ticks}={full_ticks} ticks, "
            f"{high_ticks / full_ticks:.3%} high",
        )

    short_ticks = tuned_full_ticks(TOP, tune_code)
    long_ticks = tuned_full_ticks(TOP + 1, tune_code)
    top_ticks = short_ticks * (1 - 574 / 1024) + long_ticks * (574 / 1024)
    top_hz = PIXEL_CLOCK / top_ticks
    bottom_hz = PIXEL_CLOCK / tuned_full_ticks(BOTTOM + 1, tune_code)
    check(
        f"{tune_name} tuning fundamentals",
        top_window[0] <= top_hz <= top_window[1]
        and bottom_window[0] <= bottom_hz <= bottom_window[1],
        f"top {top_hz:.2f} Hz, bottom {bottom_hz:.2f} Hz",
    )

reference_top_hz = PIXEL_CLOCK / (2 * (TOP + 574 / 1024))
reference_bottom_hz = PIXEL_CLOCK / (2 * (BOTTOM + 1))
check(
    "internal reference contour",
    628.3 <= reference_top_hz <= 628.5
    and 505.1 <= reference_bottom_hz <= 505.3,
    f"top {reference_top_hz:.2f} Hz, bottom {reference_bottom_hz:.2f} Hz",
)


check(
    "monotonic slowdown",
    all(a < b for a, b in zip(intervals, intervals[1:])),
    f"step intervals {intervals}",
)
control_intervals = [interval for _, interval in control_bands] + [
    int(control_last.group(1))
]
check(
    "monotonic recovery slowdown",
    all(a < b for a, b in zip(control_intervals, control_intervals[1:])),
    f"step intervals {control_intervals}",
)

pip = Beeper()
pip.run_ms(19.5, True)
check("19.5 ms pip", pip.half == TOP, f"{pip.hz:.2f} Hz at the principal divider")

early_descent = Beeper()
early_descent.run_ms(48, True)
check("48 ms early descent", 560 <= early_descent.hz <= 567, f"{early_descent.hz:.2f} Hz")

emphasis_100 = Beeper()
emphasis_100.run_ms(100, True)
check("100 ms emphasis", 524 <= emphasis_100.hz <= 527, f"{emphasis_100.hz:.2f} Hz")

emphasis_120 = Beeper()
emphasis_120.run_ms(120, True)
check("120 ms emphasis", 515 <= emphasis_120.hz <= 519, f"{emphasis_120.hz:.2f} Hz")

sustained = Beeper()
sustained.run_ms(211, True)
check(
    "sustained floor",
    sustained.half == BOTTOM and 505.1 <= sustained.hz <= 505.3,
    f"{sustained.hz:.2f} Hz after 211 ms",
)
check("driven amplitude", sustained.amp == 255, f"full envelope level {sustained.amp}")

soft_landing = Beeper()
soft_landing.run_ms(200, True)
check(
    "soft floor approach",
    BOTTOM - 4 <= soft_landing.half < BOTTOM and 505.7 <= soft_landing.hz <= 506.4,
    f"{soft_landing.hz:.2f} Hz with {BOTTOM - soft_landing.half} divider steps remaining at 200 ms",
)

release = Beeper()
release.run_ms(211, True)
release.tick(False)
check(
    "release entry",
    not release.q_prev and release.amp == 255,
    f"entered at {release.hz:.2f} Hz and level {release.amp}",
)
release.run_ms(40, False)
check(
    "audible upward release",
    540 <= release.hz <= 544 and 36 <= release.amp <= 42,
    f"{release.hz:.2f} Hz at level {release.amp} after 40 ms",
)
check(
    "RC-like release level",
    -17.0 <= 20 * math.log10(release.amp / 255) <= -15.5,
    f"{20 * math.log10(release.amp / 255):.1f} dB after 40 ms",
)
release.run_ms(38, False)
check(
    "quiet residual tail",
    release.amp <= 7 and 20 * math.log10(release.amp / 255) <= -30,
    f"level {release.amp} ({20 * math.log10(release.amp / 255):.1f} dB) after 78 ms",
)
release.run_ms(19, False)
check(
    "silent recovery",
    release.amp == 0
    and not release.q_prev
    and release.half == release.control_half,
    f"level {release.amp}, synchronized at {release.hz:.2f} Hz",
)

retrigger = Beeper()
retrigger.run_ms(120, True)
retrigger.run_ms(5, False)
instantaneous = retrigger.half
instantaneous_amp = retrigger.amp
retrigger.tick(True)
check(
    "retrigger continuity",
    retrigger.half == instantaneous
    and retrigger.amp == instantaneous_amp
    and retrigger.q_prev
    and retrigger.on_ticks == 0,
    f"resumed at divider {retrigger.half}, level {retrigger.amp}",
)
retrigger.run_ms(2, True)
check(
    "retrigger settling",
    retrigger.half < instantaneous and retrigger.amp > instantaneous_amp,
    f"pitch recovery continued at {retrigger.hz:.2f} Hz while level rose "
    f"{instantaneous_amp}->{retrigger.amp}",
)

retrigger.run_ms(98, True)
fresh_100 = Beeper()
fresh_100.run_ms(100, True)
check(
    "non-additive retrigger",
    retrigger.half == fresh_100.half,
    f"divider {retrigger.half} rejoined fresh contour {fresh_100.half} "
    f"without stacking below live {instantaneous}",
)

concentration = Beeper()
concentration.run_ms(120, True)
first_trough_hz = concentration.hz
concentration.run_ms(12, False)
second_pulse_hz = []
for _ in range(50):
    concentration.run_ms(1, True)
    second_pulse_hz.append(concentration.hz)
second_crest_hz = max(second_pulse_hz)
principal_interval = 1200 * math.log2(second_crest_hz / 628.4)
trough_interval = 1200 * math.log2(second_crest_hz / first_trough_hz)
check(
    "Concentration second-pulse crest",
    539 <= second_crest_hz <= 542,
    f"{second_crest_hz:.2f} Hz after a representative 120/12ms retrigger",
)
check(
    "Concentration pitch windows",
    -265 <= principal_interval <= -255 and 70 <= trough_interval <= 80,
    f"{principal_interval:.1f} cents from principal, "
    f"+{trough_interval:.1f} cents from first trough",
)

# FLiP's Q-Sound Test drives the same long note followed by selectable low gaps.
# The effective gaps come from the recorded pulse periods. Targets are the
# steady retrigger crests, normalized to the 628.4Hz fresh pitch in each file.
q_test_hardware = {
    30: (60.238, 596.48),
    50: (105.499, 609.24),
    80: (160.692, 620.54),
    100: (205.884, 623.75),
}
q_test_model = {}
for setting, (gap_ms, _) in q_test_hardware.items():
    sequence = Beeper()
    sequence.run_ms(205.884, True)
    sequence.run_ms(gap_ms, False)
    retrigger_hz = []
    for _ in range(45):
        sequence.run_ms(1, True)
        retrigger_hz.append(sequence.hz)
    q_test_model[setting] = max(retrigger_hz)

q_test_rmse = math.sqrt(
    sum(
        (q_test_model[setting] - target) ** 2
        for setting, (_, target) in q_test_hardware.items()
    ) / len(q_test_hardware)
)
check(
    "Q-Sound Test gap-dependent retrigger",
    q_test_rmse <= 0.8
    and all(
        q_test_model[a] < q_test_model[b]
        for a, b in zip(q_test_model, list(q_test_model)[1:])
    ),
    f"{q_test_rmse:.2f}Hz RMS error across "
    + ", ".join(
        f"{setting}={q_test_model[setting]:.1f}Hz" for setting in q_test_model
    ),
)

# Preserve the game cadence as a monotonic family without treating earlier
# frame-derived acoustic estimates as direct Q timing measurements.
gunfighter_model = []
for gap_frames in (2, 3, 4, 5, 6, 9):
    sequence = Beeper()
    sequence.run_ms(7 * 1000 / 60, True)
    sequence.run_ms(gap_frames * 1000 / 60, False)
    sequence.run_ms(11, True)
    gunfighter_model.append(sequence.hz)
check(
    "Gunfighter retrigger ordering",
    all(a < b for a, b in zip(gunfighter_model, gunfighter_model[1:])),
    ", ".join(
        f"{gap}f={hz:.1f}Hz"
        for gap, hz in zip((2, 3, 4, 5, 6, 9), gunfighter_model)
    ),
)

rapid = Beeper()
for _ in range(4):
    rapid.run_ms(15, True)
    rapid.run_ms(35, False)
check(
    "20 Hz short pulses",
    rapid.half == TOP,
    f"remained at the {rapid.hz:.2f} Hz principal pitch",
)

cactus_spam = Beeper()
cactus_troughs = []
for _ in range(6):
    cactus_spam.run_ms(120, True)
    cactus_troughs.append(cactus_spam.half)
    cactus_spam.run_ms(40, False)
check(
    "repeated-note bound",
    all(half <= cactus_troughs[0] for half in cactus_troughs[1:]),
    f"no cumulative lowering across dividers {cactus_troughs}",
)
