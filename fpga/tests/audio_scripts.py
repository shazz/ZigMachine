"""The stimulus for tests/test_rtl_audio.py: the scripts tests/audio_ref/audio_ref.zig
and the CXXRTL testbenches (tests/tb/audio_script.h) both play, and the helpers
that read what they made."""

import random
import struct
from pathlib import Path


def write_pcm_script(d: Path) -> None:
    """Every Paula path: loops, one-shots, clamping, retrigger, SetPos/Active, reset."""
    rnd = random.Random(0x5A11)
    pcm = bytes([0x80] * 256 + [0x7F] * 256) + bytes(rnd.randrange(256) for _ in range(7680))
    (d / "pcm.bin").write_bytes(pcm)
    lines = ["pcm pcm.bin", "run 3"]
    for c in range(4):  # all four at full volume on -128, then +127: both clamps
        lines += [f"trig {c} 0 256 0 256 0", f"vol {c} 256", f"step {c} 65536"]
    lines += ["run 300"] + [f"trig {c} 256 256 0 256 0" for c in range(4)] + ["run 300", "reset", "run 40"]
    # Channel 0 alone; POS and CTRL written while its sample is being mixed land after it.
    lines += ["trig 0 1000 500 0 500 0", "vol 0 200", "step 0 70000", "run 20", "mid pos 0 7", "run 5"]
    lines += ["mid act 0 0", "run 5", "act 0 1", "run 5", "mid pos 0 300", "run 9", "reset", "run 2"]
    lines += [f"vol {c} {v}" for c, v in enumerate((256, 64, 255, 0))]
    for _ in range(60):
        lines.append(random_op(rnd))
        lines.append(f"run {rnd.randrange(1, 400)}")
    (d / "pcm.txt").write_text("\n".join(lines) + "\n")


def random_op(rnd: random.Random) -> str:
    c, op = rnd.randrange(4), rnd.choice(["trig", "trig", "step", "vol", "pan", "pos", "act"])
    if op == "trig":
        data, n = rnd.randrange(512, 6000), rnd.randrange(0, 2000)
        ll = rnd.choice([0, 1, max(2, n // rnd.randrange(1, 8))]) if n else 0
        ls = rnd.randrange(0, n - ll + 1) if n else 0
        return f"trig {c} {data} {n} {ls} {ll} {rnd.randrange(-128, 129)}"
    vals = {
        "step": rnd.choice([65536, 32768, 1, 0, rnd.randrange(1, 4 << 16)]),
        "vol": rnd.choice([0, 256, rnd.randrange(0, 257)]),
        "pan": rnd.choice([-128, 0, 128, rnd.randrange(-128, 129)]),
        "pos": rnd.randrange(0, 200),
        "act": rnd.randrange(2),
    }
    return f"{op} {c} {vals[op]}"


ENV = ["ym 7 62", "ym 11 64", "ym 12 0", "ym 8 16"]  # A: tone through the envelope; B, C: constant levels


def write_ym_script(d: Path) -> None:
    """The YM by itself: tones, noise, the envelope shapes, R13 = 0xFF, reset.
    Shapes 11 and 15 have their own script (ym_hold.txt): ym.zig holds them at
    the wrong end (test_the_envelope_holds_as_the_datasheet_says)."""
    lines = ["ym 7 56", "ym 0 238", "ym 1 0", "ym 8 15", "run 4410", "ym 2 100", "ym 9 12", "run 4410"]
    lines += ["ym 7 54", "ym 6 5", "ym 10 13", "ym 4 32", "ym 5 1", "run 4410"]  # noise on C
    for shape in (8, 10, 12, 14, 0, 4, 9, 13):
        lines += [*ENV, f"ym 13 {shape}", "run 2205", "ym 13 255", "run 2205"]
    lines += ["reset", "run 2205"]
    (d / "ym.txt").write_text("\n".join(lines) + "\n")
    hold = ["ym 0 238", "ym 1 0"]
    for shape in (11, 15):
        hold += [*ENV, f"ym 13 {shape}", "run 4410"]
    (d / "ym_hold.txt").write_text("\n".join(hold) + "\n")


def left(path: Path) -> list[int]:
    data = path.read_bytes()
    return list(struct.unpack(f"<{len(data) // 2}h", data))[0::2]


def ac_rms(x: list[int]) -> float:
    mean = sum(x) / len(x)
    return (sum((v - mean) ** 2 for v in x) / len(x)) ** 0.5
