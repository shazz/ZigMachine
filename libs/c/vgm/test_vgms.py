"""Our own single-feature VGMs (libs/c/vgm/README.md): each exercises one part of the chips, for the
local Gens comparison and the harness's hashes and --break tests (apps/harness/vgm_check.mjs).

    python3 libs/c/vgm/test_vgms.py <out dir>      writes <name>.vgm for every test below
"""
import math
import sys
from pathlib import Path

from vgm_write import Vgm, freq, key, patch

OFF = {"tl": 127}
SEC = 44100


def fnum_of(hz, block):
    return round(hz * (1 << 20) / (7670453 / 144) / (1 << (block - 1)))


def note(v, ch, hz, on, off=SEC // 10, ops=0xF):
    block = 4
    while fnum_of(hz, block) > 2047:
        block += 1
    while fnum_of(hz, block) < 1024 and block > 0:
        block -= 1
    freq(v, ch, block, fnum_of(hz, block))
    key(v, ch, ops)
    v.wait(on)
    key(v, ch, 0)
    v.wait(off)


def init(v):
    for reg, val in ((0x22, 0), (0x27, 0), (0x2B, 0)):
        v.ym_write(0, reg, val)


def t_algos(v):
    """Every algorithm, modulators at TL 20-30: the connections and their delays."""
    for alg in range(8):
        mod = {"tl": 24, "mul": 2, "ar": 31, "dr": 6, "sl": 4}
        car = {"tl": 0, "mul": 1, "ar": 31, "dr": 2, "sl": 2}
        ops = [mod, mod | {"mul": 3}, mod | {"mul": 1}, car] if alg < 4 else [mod, car, mod, car]
        patch(v, 0, alg, 0, ops if alg < 7 else [car] * 4)
        note(v, 0, 220, SEC // 2)


def t_feedback(v):
    """Op 1 alone at feedback 0..7."""
    for fb in range(8):
        patch(v, 1, 7, fb, [{"tl": 0, "ar": 31}, OFF, OFF, OFF])
        note(v, 1, 330, SEC // 3)


def t_envelope(v):
    """Attack, decay, sustain and release rates; key scaling over the octaves."""
    for ar, dr, sr, sl, rr in ((12, 8, 4, 6, 6), (20, 14, 0, 2, 3), (31, 4, 10, 10, 10), (8, 0, 0, 0, 1)):
        patch(v, 2, 7, 0, [OFF, OFF, OFF, {"ar": ar, "dr": dr, "sr": sr, "sl": sl, "rr": rr}])
        note(v, 2, 440, SEC // 2, SEC // 2)
    for ks in range(4):
        patch(v, 2, 7, 0, [OFF, OFF, OFF, {"ks": ks, "ar": 14, "dr": 9, "sl": 8, "rr": 7}])
        for hz in (110, 880, 3520):
            note(v, 2, hz, SEC // 5, SEC // 10)


def t_lfo(v):
    """The LFO at each frequency, AM 3 and PM 7 on an FM pair."""
    for f in range(8):
        v.ym_write(0, 0x22, 8 | f)
        patch(v, 3, 4, 3, [{"tl": 30, "am": 1}, {"tl": 0, "am": 1}, {"tl": 30}, {"tl": 4}], ams=f & 3, pms=7 - f)
        note(v, 3, 262, SEC // 2)
    v.ym_write(0, 0x22, 0)


def t_detune(v):
    """Detune 0..7 and multiples 0..15 on op 4, beside an undetuned op 3."""
    for dt in range(8):
        patch(v, 4, 7, 0, [OFF, OFF, {"tl": 8}, {"tl": 8, "dt": dt}])
        note(v, 4, 1500, SEC // 5, 0)
    for mul in range(16):
        patch(v, 4, 7, 0, [OFF, OFF, OFF, {"tl": 6, "mul": mul}])
        note(v, 4, 180, SEC // 8, 0)


def t_ssg(v):
    """SSG-EG shapes 8..15."""
    for shape in range(8, 16):
        patch(v, 5, 7, 0, [OFF, OFF, OFF, {"ar": 31, "dr": 24, "sr": 20, "sl": 15, "ssg": shape}])
        note(v, 5, 392, SEC // 2)


def t_ch3(v):
    """Channel 3's special mode: four operators at four pitches."""
    v.ym_write(0, 0x27, 0x40)
    patch(v, 2, 7, 0, [{"tl": 10}] * 4)
    for reg, (blk, hz) in zip((0xAD, 0xAE, 0xAC), ((4, 300), (4, 450), (4, 600)), strict=True):
        f = fnum_of(hz, blk)
        v.ym_write(0, reg, blk << 3 | f >> 8)
        v.ym_write(0, reg - 4, f & 0xFF)
    note(v, 2, 150, SEC)
    v.ym_write(0, 0x27, 0)


def t_dac(v):
    """The DAC on channel 6: a decaying 8-bit tone burst played as 0x8n writes, panned."""
    pcm = bytes(128 + int(100 * math.exp(-i / 1500) * math.sin(i * 0.31)) for i in range(6000))
    v.data_block(pcm)
    v.ym_write(1, 0xB6, 0xC0)
    v.ym_write(0, 0x2B, 0x80)
    for pan in (0xC0, 0x80, 0x40):
        v.ym_write(1, 0xB6, pan)
        v.pcm_seek(0)
        for _ in range(len(pcm)):
            v.dac_wait(3)
    v.ym_write(0, 0x2B, 0)


def t_psg(v):
    """The PSG: three tones over the attenuations, white and periodic noise at each rate."""
    for c, period in ((0, 254), (1, 190), (2, 127)):
        v.psg_write(0x80 | c << 5 | period & 15)
        v.psg_write(period >> 4)
        for att in range(0, 16, 3):
            v.psg_write(0x90 | c << 5 | att)
            v.wait(SEC // 10)
        v.psg_write(0x9F | c << 5)
    for nf in range(8):
        v.psg_write(0xE0 | nf)
        v.psg_write(0xF2)
        v.wait(SEC // 4)
    v.psg_write(0xFF)


TESTS = {"algos": t_algos, "feedback": t_feedback, "envelope": t_envelope, "lfo": t_lfo, "detune": t_detune,
         "ssg": t_ssg, "ch3": t_ch3, "dac": t_dac, "psg": t_psg}


def build(name):
    v = Vgm()
    init(v)
    TESTS[name](v)
    v.wait(SEC // 10)
    return v.bytes()


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name in TESTS:
        (out / f"{name}.vgm").write_bytes(build(name))


if __name__ == "__main__":
    main()
