"""KESTREL FM, VGM TEST's tune: an original 16-bar loop written by this script (MIT, like the repo; no
third-party music), every part of the chips busy at once so it doubles as the BARD load bench.

    python3 libs/c/vgm/make_tune.py docs/music/kestrel_fm.vgm [bars, default 16: fewer for the BARD bench image]

Six FM channels (bass with feedback, an LFO-vibrato lead, a pad, two arpeggios, channel 6 on the DAC
for drums synthesised here) and the PSG (a square counter-line and noise hi-hats). 125 BPM, A minor.
"""
import math
import sys

from vgm_write import Vgm, freq, key
from vgm_write import patch as raw_patch

SEC = 44100
STEP = SEC * 60 // 125 // 4  # a sixteenth
CHORDS = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # Am F C G (MIDI notes)
LEAD = [76, 0, 74, 72, 74, 0, 76, 79, 77, 0, 76, 74, 72, 0, 71, 72]


CARRIERS = {0: (3,), 1: (3,), 2: (3,), 3: (3,), 4: (1, 3), 5: (1, 2, 3), 6: (1, 2, 3), 7: (0, 1, 2, 3)}
MIX_TL = 10  # every carrier this much quieter (0.75 dB a step): the six channels and the DAC sum below clipping


def patch(v, ch, alg, fb, ops, **kw):
    ops = [o | {"tl": o.get("tl", 0) + MIX_TL} if i in CARRIERS[alg] else o for i, o in enumerate(ops)]
    raw_patch(v, ch, alg, fb, ops, **kw)


def fnum(note):
    """The lowest block whose F-number fits 11 bits (YM2612: hz = fnum x chip rate x 2^(block - 1) / 2^20)."""
    hz = 440 * 2 ** ((note - 69) / 12)
    for block in range(8):
        f = round(hz * (1 << 20) / (7670453 / 144) / 2 ** (block - 1))
        if f <= 2047:
            return block, f
    return 7, 2047


def play(v, ch, note):
    key(v, ch, 0)
    if note:
        freq(v, ch, *fnum(note))
        key(v, ch)


def drums():
    kick = bytes(128 + int(110 * math.exp(-i / 900) * math.sin(2 * math.pi * 55 * (1 + 2 * math.exp(-i / 300)) * i / 8000))
                 for i in range(2400))
    seed, snare = 12345, bytearray()
    for i in range(2000):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((seed >> 16) & 255) - 128
        snare.append(128 + int(math.exp(-i / 500) * (0.7 * noise + 40 * math.sin(i * 0.25))))
    return kick, bytes(snare)


def setup(v):
    v.ym_write(0, 0x22, 0x08 | 3)  # LFO on, 6.37 Hz
    v.ym_write(0, 0x27, 0)
    patch(v, 0, 0, 6, [{"tl": 28, "mul": 1, "dr": 8, "sl": 3}, {"tl": 36, "mul": 3, "dr": 10, "sl": 5},
                       {"tl": 30, "mul": 1, "dr": 6, "sl": 4}, {"tl": 2, "dr": 4, "sl": 6, "rr": 8}])
    patch(v, 1, 4, 3, [{"tl": 34, "mul": 2}, {"tl": 6, "dr": 3, "sl": 3}, {"tl": 40, "mul": 4},
                       {"tl": 10, "dr": 3, "sl": 3}], pms=3, ams=1)
    patch(v, 2, 7, 0, [{"tl": 30, "ar": 12, "rr": 5, "am": 1}, {"tl": 32, "ar": 10, "rr": 5, "dt": 3},
                       {"tl": 32, "ar": 11, "rr": 5, "dt": 7}, {"tl": 30, "ar": 12, "rr": 5}], ams=2)
    for ch in (3, 4):
        patch(v, ch, 5, 4, [{"tl": 30, "mul": 1, "dr": 12, "sl": 8}, {"tl": 14, "mul": 2, "dr": 9, "sl": 9},
                            {"tl": 16, "mul": 1, "dr": 9, "sl": 9}, {"tl": 18, "mul": 4, "dr": 11, "sl": 10}],
              pan=0x80 if ch == 3 else 0x40)
    v.ym_write(1, 0xB6, 0xC0)
    v.ym_write(0, 0x2B, 0x80)  # channel 6 is the DAC


def psg(v, step, bar, chord):
    if step % 2 == 0:  # hi-hat: white noise, short
        v.psg_write(0xE4)
        v.psg_write(0xF0 | (3 if step % 4 == 2 else 6))
    else:
        v.psg_write(0xFF)
    if step % 4 == 0:
        note = chord[(step // 4 + bar) % 3] + 12
        period = round(3579545 / (32 * 440 * 2 ** ((note - 69) / 12)))
        v.psg_write(0x80 | (period & 15))
        v.psg_write(period >> 4)
        v.psg_write(0x90 | 5)
    elif step % 4 == 2:
        v.psg_write(0x90 | 10)


def bar_steps(v, bar, kick_at, snare_at):
    chord = CHORDS[bar // 4 % 4]
    for s in range(16):
        if s % 4 == 0:
            play(v, 0, chord[0] - 24 + (12 if s == 8 else 0))
        if s == 0:
            play(v, 2, chord[1])
        if bar % 2 == 1 or s >= 8:
            play(v, 1, LEAD[s] + (0 if bar % 8 < 4 else -2) if LEAD[s] else 0)
        play(v, 3, chord[s % 3] + 12)
        play(v, 4, chord[(s + 1) % 3] + 24 if s % 2 else 0)
        psg(v, s, bar, chord)
        drum = kick_at if s in (0, 6, 8) else snare_at if s in (4, 12) else None
        if drum is not None:
            v.pcm_seek(drum[0])
            for _ in range(min(drum[1], STEP // 5)):
                v.dac_wait(5)
            v.wait(STEP - min(drum[1], STEP // 5) * 5)
        else:
            v.wait(STEP)


def main():
    v = Vgm()
    kick, snare = drums()
    v.data_block(kick + snare)
    setup(v)
    v.loop_here()
    for bar in range(int(sys.argv[2]) if len(sys.argv) > 2 else 16):
        bar_steps(v, bar, (0, len(kick)), (len(kick), len(snare)))
    open(sys.argv[1], "wb").write(v.bytes())


if __name__ == "__main__":
    main()
