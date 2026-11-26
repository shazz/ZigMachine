"""Kestrel Racing's three tunes (R82 M5 step 4, replacing M4's placeholders): ORIGINAL music, the scores in
tools/racer/tunes_score.py (MIT, like the repo; no third-party music, nothing derived from any game's soundtrack).

    python3 tools/racer/make_tunes.py site/music        writes kr_title.vgm, kr_race.vgm, kr_results.vgm
    python3 tools/racer/make_tunes.py --check site/music  the committed files = what this script writes

Arranged on FM 1-4 and PSG tones 1-2 only: FM 5-6, PSG tone 3 and the noise are the cart's sound effects
(zg.bard.fm SFX_DEFAULT), so the tunes never write them and nothing of the tune is lost under the effects.
FM 1 bass, FM 2 lead, FM 3 pad, FM 4 drums (one patch: the kick with operator 1 silent and a pitch drop, the
snare with operator 1 at full feedback); PSG 1 the arpeggio, PSG 2 the ticks. No DAC, no LFO: the effects'
patches see a quiet global state. libs/c/vgm/make_tune.py's method (vgm_write).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Final

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "libs/c/vgm"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from tunes_score import TUNES, Section, Tune
from vgm_write import Vgm, freq, key, patch

SEC: Final = 44100
YM_CLOCK: Final = 7670453
PSG_CLOCK: Final = 3579545
BASS, LEAD, PAD, DRUM = 0, 1, 2, 3  # FM channels 1-4

PATCHES: Final = (
    (0, 6, [{"tl": 30, "mul": 1, "dr": 8, "sl": 3}, {"tl": 38, "mul": 2, "dr": 10, "sl": 5},
            {"tl": 30, "mul": 1, "dr": 6, "sl": 4}, {"tl": 15, "dr": 5, "sl": 6, "rr": 9}]),
    (4, 5, [{"tl": 34, "mul": 2}, {"tl": 19, "dr": 3, "sl": 2, "rr": 7}, {"tl": 44, "mul": 4},
            {"tl": 21, "dr": 3, "sl": 2, "rr": 7}]),
    (7, 0, [{"tl": 40, "ar": 14, "rr": 5}, {"tl": 42, "ar": 12, "rr": 5, "dt": 3},
            {"tl": 42, "ar": 13, "rr": 5, "dt": 7}, {"tl": 127, "ar": 14, "rr": 5}]),
    (0, 7, [{"tl": 127, "mul": 1}, {"tl": 28, "mul": 1, "dr": 20, "sl": 15, "rr": 15},
            {"tl": 24, "mul": 1, "dr": 18, "sl": 15, "rr": 15}, {"tl": 10, "dr": 13, "sl": 15, "rr": 15}]),
)
NAMES: Final = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUALITY: Final = {"": (0, 4, 7), "m": (0, 3, 7), "dim": (0, 3, 6), "maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10),
                  "7": (0, 4, 7, 10)}
KICK_TL1, SNARE_TL1 = 127, 0  # FM 4 operator 1: silent for the kick, the noise source for the snare


def pitch(name: str) -> tuple[int, str]:
    """'F#' + the rest -> (semitone 0..11, the rest)."""
    n, rest = NAMES[name[0]], name[1:]
    if rest[:1] in "#b" and rest:
        n, rest = (n + (1 if rest[0] == "#" else -1)) % 12, rest[1:]
    return n, rest


def note(text: str) -> int:
    """'C#5' -> MIDI 73."""
    n, octave = pitch(text)
    return 12 * (int(octave) + 1) + n


def chord(name: str) -> list[int]:
    """A chord name -> its tones from the root in octave 3 (MIDI 48..59)."""
    root, quality = pitch(name)
    return [48 + root + i for i in QUALITY[quality]]


def lead_bar(text: str) -> list[int | None]:
    """'E5:2 -:2 ...' -> 16 steps: a MIDI note where one starts, 0 a rest, None a hold."""
    steps: list[int | None] = []
    for tok in text.split():
        name, length = tok.split(":")
        steps += [0 if name == "-" else note(name)] + [None] * (int(length) - 1)
    if len(steps) != 16:
        raise ValueError(f"lead bar {text!r}: {len(steps)} sixteenths, not 16")
    return steps


def fnum(midi: int) -> tuple[int, int]:
    """The lowest block whose F-number fits 11 bits (YM2612: hz = fnum x clock / 144 x 2^(block - 1) / 2^20)."""
    hz = 440 * 2 ** ((midi - 69) / 12)
    for block in range(8):
        f = round(hz * (1 << 20) / (YM_CLOCK / 144) / 2 ** (block - 1))
        if f <= 2047:
            return block, f
    return 7, 2047


def play(v: Vgm, ch: int, midi: int) -> None:
    key(v, ch, 0)
    if midi:
        freq(v, ch, *fnum(midi))
        key(v, ch)


def tone(v: Vgm, c: int, midi: int, att: int) -> None:
    """PSG tone c (0 or 1 here: tone 3 is the effects') at a MIDI note (0: keep the pitch), attenuation att (15 off)."""
    if midi:
        period = max(1, min(1023, round(PSG_CLOCK / (32 * 440 * 2 ** ((midi - 69) / 12)))))
        v.psg_write(0x80 | c << 5 | (period & 15))
        v.psg_write(period >> 4)
    v.psg_write(0x90 | c << 5 | att)


def setup(v: Vgm) -> None:
    v.ym_write(0, 0x22, 0)  # no LFO
    v.ym_write(0, 0x27, 0)
    for ch, (alg, fb, ops) in enumerate(PATCHES):
        patch(v, ch, alg, fb, ops, pan=0xC0)
    for c in range(4):  # every PSG channel off; tones 1-2 are the tune's
        v.psg_write(0x90 | c << 5 | 15)


def bass(v: Vgm, sec: Section, tones: list[int], s: int) -> None:
    c = sec.bass[s]
    if c == "-":
        play(v, BASS, 0)
    elif c in "ROF":
        play(v, BASS, tones[0] - 12 + {"R": 0, "O": 12, "F": 7}[c])


def drums(v: Vgm, c: str) -> bool:
    """A drum hit at this step (the kick's pitch drop is due a quarter step later: True)."""
    if c not in "KS":
        return False
    v.ym_write(DRUM // 3, 0x40 + DRUM % 3, KICK_TL1 if c == "K" else SNARE_TL1)  # operator 1's TL
    play(v, DRUM, 45 if c == "K" else 62)
    return c == "K"


def arp(v: Vgm, sec: Section, tones: list[int], s: int) -> None:
    c = sec.arp[s]
    if c.isdigit():
        tone(v, 0, tones[int(c) % len(tones)] + 24, 7)
    else:
        tone(v, 0, 0, 11)


def step(v: Vgm, sec: Section, bar: int, s: int, ticks: int) -> None:
    """One sixteenth of a bar: every voice's writes at its start, the kick's drop and the tick's end a quarter in."""
    tones = chord(sec.chords[bar])
    bass(v, sec, tones, s)
    lead = lead_bar(sec.lead[bar])[s]
    if lead is not None:
        play(v, LEAD, lead)
    if s == 0:
        play(v, PAD, tones[1 + bar % 2] + 12)
    arp(v, sec, tones, s)
    kick = drums(v, sec.drums[s])
    if sec.hats[s] == "x":
        tone(v, 1, 112, 10)
    q = ticks // 4
    v.wait(q)
    if kick:
        freq(v, DRUM, *fnum(33))
    tone(v, 1, 0, 15)
    v.wait(ticks - q)


def make(tune: Tune) -> bytes:
    v = Vgm()
    setup(v)
    v.loop_here()
    ticks = SEC * 60 // tune.bpm // 4  # a sixteenth
    for name in tune.order:
        sec = tune.sections[name]
        for bar in range(8):
            for s in range(16):
                step(v, sec, bar, s, ticks)
    return v.bytes()


def main() -> None:
    check = "--check" in sys.argv
    out = Path(next(a for a in sys.argv[1:] if a != "--check"))
    bad = []
    for name, tune in TUNES.items():
        data = make(tune)
        if check:
            if not (out / name).is_file() or (out / name).read_bytes() != data:
                bad.append(name)
        else:
            (out / name).write_bytes(data)
            print(f"{out / name}: {len(data)} bytes")
    if bad:
        sys.exit(f"make_tunes --check: {', '.join(bad)} differ from what tools/racer/make_tunes.py writes")
    if check:
        print("make_tunes --check: the three tunes are the script's")


if __name__ == "__main__":
    main()
