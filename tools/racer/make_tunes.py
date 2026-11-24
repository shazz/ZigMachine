"""Kestrel Racing's three PLACEHOLDER tunes (R82 M4): original loops written by this script (MIT, like the repo;
no third-party music, nothing derived from any game's soundtrack), replaceable by the final tunes (M5).

    python3 tools/racer/make_tunes.py site/music        writes kr_title.vgm, kr_race.vgm, kr_results.vgm
    python3 tools/racer/make_tunes.py --check site/music  the committed files = what this script writes

Arranged on FM 1-4 and PSG tones 1-2 only: FM 5-6, PSG tone 3 and the noise are the cart's sound effects
(zg.bard.fm SFX_DEFAULT), so the tunes never write them and nothing of the tune is lost under the effects.
No DAC, no LFO: the effects' patches see a quiet global state. libs/c/vgm/make_tune.py's method (vgm_write).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "libs/c/vgm"))
from vgm_write import Vgm, freq, key, patch  # noqa: E402

SEC = 44100
YM_CLOCK = 7670453
PSG_CLOCK = 3579545

BASS = (0, 6, [{"tl": 30, "mul": 1, "dr": 8, "sl": 3}, {"tl": 38, "mul": 2, "dr": 10, "sl": 5},
               {"tl": 30, "mul": 1, "dr": 6, "sl": 4}, {"tl": 12, "dr": 5, "sl": 6, "rr": 9}])
LEAD = (4, 4, [{"tl": 36, "mul": 2}, {"tl": 16, "dr": 4, "sl": 3, "rr": 7}, {"tl": 42, "mul": 3},
               {"tl": 18, "dr": 4, "sl": 3, "rr": 7}])
PAD = (7, 0, [{"tl": 36, "ar": 14, "rr": 5}, {"tl": 38, "ar": 12, "rr": 5, "dt": 3},
              {"tl": 38, "ar": 13, "rr": 5, "dt": 7}, {"tl": 36, "ar": 14, "rr": 5}])
PLUCK = (5, 5, [{"tl": 32, "mul": 1, "dr": 12, "sl": 8}, {"tl": 22, "mul": 2, "dr": 10, "sl": 9},
                {"tl": 24, "mul": 1, "dr": 10, "sl": 9}, {"tl": 26, "mul": 4, "dr": 12, "sl": 10}])


def fnum(note):
    """The lowest block whose F-number fits 11 bits (YM2612: hz = fnum x clock / 144 x 2^(block - 1) / 2^20)."""
    hz = 440 * 2 ** ((note - 69) / 12)
    for block in range(8):
        f = round(hz * (1 << 20) / (YM_CLOCK / 144) / 2 ** (block - 1))
        if f <= 2047:
            return block, f
    return 7, 2047


def play(v, ch, note):
    key(v, ch, 0)
    if note:
        freq(v, ch, *fnum(note))
        key(v, ch)


def tone(v, c, note, att):
    """PSG tone c (0 or 1 here: tone 3 is the effects') at a MIDI note, attenuation att (15 off)."""
    if note:
        period = min(1023, round(PSG_CLOCK / (32 * 440 * 2 ** ((note - 69) / 12))))
        v.psg_write(0x80 | c << 5 | (period & 15))
        v.psg_write(period >> 4)
    v.psg_write(0x90 | c << 5 | att)


def setup(v, pans=(0xC0, 0xC0, 0xC0, 0xC0)):
    v.ym_write(0, 0x22, 0)  # no LFO
    v.ym_write(0, 0x27, 0)
    for ch, (alg, fb, ops) in enumerate((BASS, LEAD, PAD, PLUCK)):
        patch(v, ch, alg, fb, ops, pan=pans[ch])
    for c in range(4):  # every PSG channel off; tones 1-2 are the tune's
        v.psg_write(0x90 | c << 5 | 15)


# Each tune: (bpm, chords as MIDI triads, a 16-step lead per two bars of chords, bass pattern, bars).
TUNES = {
    "kr_title.vgm": dict(bpm=118, bars=16, chords=[(52, 55, 59), (48, 52, 55), (55, 59, 62), (50, 54, 57)],  # Em C G D
                         lead=[71, 0, 74, 0, 76, 74, 71, 0, 69, 0, 71, 67, 0, 66, 67, 0],
                         bass=[1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0], pluck_oct=24, psg_oct=12),
    "kr_race.vgm": dict(bpm=150, bars=16, chords=[(57, 60, 64), (53, 57, 60), (55, 59, 62), (52, 55, 59)],  # Am F G Em
                        lead=[76, 76, 0, 79, 0, 76, 74, 0, 72, 0, 74, 76, 0, 72, 69, 0],
                        bass=[1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1], pluck_oct=24, psg_oct=24),
    "kr_results.vgm": dict(bpm=96, bars=8, chords=[(48, 52, 55, 59), (45, 48, 52, 55), (50, 53, 57, 60), (43, 47, 50, 53)],  # Cmaj7 Am7 Dm7 G7
                           lead=[64, 0, 67, 0, 71, 0, 72, 0, 71, 0, 67, 0, 64, 0, 62, 0],
                           bass=[1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0], pluck_oct=12, psg_oct=12),
}


def bar(v, t, b, step):
    chord = t["chords"][b // 2 % len(t["chords"])]
    for s in range(16):
        if t["bass"][s]:
            play(v, 0, chord[0] - 12)
        if s == 0 and b % 2 == 0:
            play(v, 2, chord[1])
        if b % 4 >= 2 or s >= 8:
            note = t["lead"][s]
            play(v, 1, note + (0 if b % 8 < 4 else -2) if note else 0)
        play(v, 3, chord[s % len(chord)] + t["pluck_oct"] if s % 2 == 0 else 0)
        if s % 4 == 0:
            tone(v, 0, chord[(s // 4 + b) % len(chord)] + t["psg_oct"], 6)
        elif s % 4 == 2:
            tone(v, 0, 0, 11)
        tone(v, 1, chord[-1] + t["psg_oct"] if s == 0 else 0, 9 if s == 0 else 15 if s == 12 else 12)
        v.wait(step)


def make(name):
    t = TUNES[name]
    v = Vgm()
    setup(v)
    v.loop_here()
    step = SEC * 60 // t["bpm"] // 4  # a sixteenth
    for b in range(t["bars"]):
        bar(v, t, b, step)
    return v.bytes()


def main():
    check = "--check" in sys.argv
    out = Path([a for a in sys.argv[1:] if a != "--check"][0])
    bad = []
    for name in TUNES:
        data = make(name)
        if check:
            if not (out / name).is_file() or (out / name).read_bytes() != data:
                bad.append(name)
        else:
            (out / name).write_bytes(data)
            print(f"{out / name}: {len(data)} bytes")
    if bad:
        sys.exit(f"make_tunes --check: {', '.join(bad)} differ from what tools/racer/make_tunes.py writes")
    if check:
        print("make_tunes --check: the three placeholder tunes are the script's")


if __name__ == "__main__":
    main()
