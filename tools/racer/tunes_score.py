"""Kestrel Racing's three tunes (R82 M5 step 4), as scores: ORIGINAL music written for this cart (MIT, like the repo).
Nothing here is copied, transcribed or adapted from any game's soundtrack. tools/racer/make_tunes.py renders them.

A section is 8 bars. Per bar: a chord (name), a lead line ("NOTE:16ths ..." summing to 16; "-" a rest). Per section,
16-step patterns repeated every bar:
  bass   R root (octave 2), O its octave, F its fifth, - key off, . hold
  drums  K kick, S snare, . nothing                          (FM 4)
  arp    0-3 a chord tone (PSG tone 1), . let it fade
  hats   x a tick (PSG tone 2), . nothing
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Section:
    chords: tuple[str, ...]
    lead: tuple[str, ...]
    bass: str
    drums: str
    arp: str
    hats: str


@dataclass(frozen=True)
class Tune:
    bpm: int
    sections: dict[str, Section]
    order: tuple[str, ...]


REST8 = ("-:16",) * 8

# "Kestrel Rising" (title, attract and the track select): D major, 128 BPM, intro + A + B + A' (32 bars, ~60 s).
TITLE = Tune(128, {
    "intro": Section(("D", "Bm", "G", "A", "D", "Bm", "G", "A"),
                     ("-:16", "-:16", "-:16", "-:8 A4:4 C#5:4", "D5:16", "-:16", "-:16", "-:8 E5:4 F#5:4"),
                     "R.......R.......", "K.......K.......", "0.1.2.1.0.1.2.1.", "................"),
    "a": Section(("D", "A", "Bm", "G", "D", "A", "G", "A"),
                 ("F#5:4 A5:4 D6:6 C#6:2", "B5:2 A5:2 E5:4 -:4 C#5:2 E5:2", "F#5:4 D5:2 F#5:2 B5:6 A5:2",
                  "G5:4 F#5:2 E5:2 D5:8", "F#5:4 A5:4 D6:4 E6:4", "F#6:6 E6:2 C#6:4 A5:4",
                  "B5:3 A5:3 G5:2 F#5:4 E5:4", "E5:4 F#5:2 G5:2 A5:8"),
                 "R..R..R.R..R..O.", "K...S...K.K.S...", "0.1.2.3.0.1.2.3.", "..x...x...x...x."),
    "b": Section(("Bm", "G", "D", "A", "Bm", "G", "Em", "A"),
                 ("D6:6 C#6:2 B5:4 F#5:4", "G5:6 A5:2 B5:4 D6:4", "A5:8 F#5:4 A5:4", "E5:12 -:4",
                  "D6:6 C#6:2 B5:4 D6:4", "E6:6 D6:2 B5:4 G5:4", "G5:4 F#5:4 E5:4 G5:4", "A5:4 C#6:4 E6:8"),
                 "R.R.R.R.R.R.R.O.", "K...S...K...S.S.", "2.1.0.1.2.1.0.1.", "x.x.x.x.x.x.x.x."),
    "a2": Section(("D", "A", "Bm", "G", "D", "A", "G", "A"),
                  ("A5:4 D6:4 F#6:6 E6:2", "C#6:2 B5:2 A5:4 -:4 E5:2 A5:2", "B5:4 F#5:2 B5:2 D6:6 C#6:2",
                   "B5:4 A5:2 G5:2 F#5:8", "A5:4 D6:4 F#6:4 E6:4", "E6:6 C#6:2 A5:4 E5:4",
                   "G5:3 F#5:3 E5:2 D5:4 C#5:4", "D5:4 E5:4 F#5:4 A5:4"),
                  "R..R..R.R..R..O.", "K...S...K.K.S.SS", "0.1.2.3.3.2.1.0.", "..x...x...x.xxx."),
}, ("intro", "a", "b", "a2"))

# "Open Throttle" (the countdown and the race): E minor, 156 BPM, A A' B C (32 bars, ~49 s).
RACE = Tune(156, {
    "a": Section(("Em", "Em", "C", "D", "Em", "Em", "C", "B"),
                 ("E5:2 -:1 E5:1 G5:2 B5:2 -:2 A5:2 G5:2 F#5:2", "E5:2 D5:2 E5:4 -:4 B4:2 D5:2",
                  "E5:2 -:1 E5:1 G5:2 C6:2 -:2 B5:2 A5:2 G5:2", "F#5:4 A5:4 D6:4 C6:2 A5:2",
                  "B5:2 -:1 B5:1 C6:2 B5:2 A5:2 G5:2 F#5:2 G5:2", "E5:6 G5:2 B5:4 E6:4",
                  "D6:2 C6:2 B5:2 A5:2 G5:2 A5:2 B5:2 C6:2", "B5:4 A5:2 F#5:2 D#5:8"),
                 "R.OR.OR.R.OR.OR.", "K...S...K.K.S...", "0.1.2.1.0.1.2.1.", "x.x.x.x.x.x.x.x."),
    "a2": Section(("Em", "Em", "C", "D", "Em", "Em", "C", "B"),
                  ("B5:2 -:1 B5:1 E6:2 B5:2 -:2 A5:2 G5:2 A5:2", "B5:2 G5:2 E5:4 -:4 E5:2 G5:2",
                   "C6:2 -:1 C6:1 E6:2 C6:2 -:2 B5:2 A5:2 B5:2", "A5:4 D6:4 F#6:4 E6:2 D6:2",
                   "E6:2 -:1 E6:1 D6:2 B5:2 A5:2 G5:2 A5:2 B5:2", "G5:6 B5:2 E6:4 G6:4",
                   "F#6:2 E6:2 D6:2 C6:2 B5:2 C6:2 D6:2 E6:2", "D#6:4 B5:2 A5:2 F#5:8"),
                  "R.OR.OR.R.OR.OR.", "K...S...K.K.S.KS", "0.1.2.3.0.1.2.3.", "xxx.xxx.xxx.xxx."),
    "b": Section(("Am", "Em", "C", "D", "Am", "Em", "F#dim", "B"),
                 ("C6:4 B5:2 A5:2 E5:4 A5:4", "B5:4 G5:2 E5:2 B4:8", "C6:2 D6:2 E6:4 D6:2 C6:2 G5:4",
                  "A5:4 D6:4 F#5:4 A5:4", "E6:4 D6:2 C6:2 A5:4 C6:4", "B5:6 G5:2 E5:8",
                  "A5:4 C6:4 D#6:4 C6:4", "B5:8 F#5:4 D#5:4"),
                 "R.R.O.R.R.R.O.R.", "K.K.S...K.K.S...", "2.1.0.1.2.1.0.1.", "x.x.x.x.x.x.x.x."),
    "c": Section(("C", "D", "Em", "Em", "C", "D", "B", "B"),
                 ("G5:8 E5:8", "F#5:8 A5:8", "B5:16", "B5:4 C6:4 D6:4 E6:4", "E6:8 C6:8", "D6:8 A5:8",
                  "D#6:8 F#6:8", "F#6:4 D#6:4 B5:4 F#5:4"),
                 "R.......R...O...", "K.......S.......", "0.1.2.3.2.1.0.1.", "..x...x...x...x."),
}, ("a", "a2", "b", "c"))

# "Podium" (the finish and the results): F major, 100 BPM, A A' (16 bars, ~38 s).
RESULTS = Tune(100, {
    "a": Section(("Fmaj7", "Dm7", "Gm7", "C7", "Fmaj7", "Am7", "Bbmaj7", "C7"),
                 ("A5:4 C6:4 E6:6 D6:2", "C6:4 A5:4 F5:8", "G5:4 Bb5:4 D6:4 C6:4", "Bb5:4 A5:2 G5:2 E5:8",
                  "F5:4 A5:4 C6:4 F6:4", "E6:6 D6:2 C6:4 A5:4", "D6:4 C6:4 Bb5:4 A5:4", "G5:8 -:8"),
                 "R.....F.R.......", "K.......S.......", "0.1.2.3.2.1.....", "....x.......x..."),
    "a2": Section(("Fmaj7", "Dm7", "Gm7", "C7", "Fmaj7", "Am7", "Bbmaj7", "C7"),
                  ("A5:4 C6:4 E6:6 D6:2", "C6:4 A5:4 F5:8", "G5:4 Bb5:4 D6:4 C6:4", "Bb5:4 A5:2 G5:2 E5:8",
                   "F5:4 A5:4 C6:4 F6:4", "E6:6 D6:2 C6:4 A5:4", "D6:4 F6:4 E6:4 D6:4", "C6:4 Bb5:4 A5:4 G5:4"),
                  "R.....F.R...F...", "K.......S...K...", "0.1.2.3.2.1.0.1.", "..x...x...x...x."),
}, ("a", "a2"))

TUNES: dict[str, Tune] = {"kr_title.vgm": TITLE, "kr_race.vgm": RACE, "kr_results.vgm": RESULTS}
