"""Register-write scripts for the POKEY testbench (tests/test_rtl_pokey.py): the
format tests/pokey_ref/pokey_ref.zig and tests/tb/pokey_tb.cpp read.

One segment per AUDCTL value, all 256 in a shuffled order, so every bit and
every combination of them runs. In each, the four AUDC distortions (bits 7-5)
rotate so that every channel plays all eight across consecutive segments, with
volume-only on about one write in eight; AUDF is mostly small so the slow bases
(15 kHz: a tick every 114 cycles) still borrow often. Mid-segment writes change
AUDF / AUDC while counting; STIMER and SKCTL init mode (polys and bases held)
come and go.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

SEGMENT_CYCLES = 2400
AUDCTL, STIMER, SKCTL = 0x8, 0x9, 0xF


@dataclass
class Script:
    lines: list[str] = field(default_factory=list)
    cycles: int = 0

    def w(self, addr: int, data: int) -> None:
        self.lines.append(f"w 0x{addr:x} 0x{data:02x}")

    def run(self, n: int) -> None:
        self.lines.append(f"run {n}")
        self.cycles += n


def _audf(rng: random.Random, slow: bool) -> int:
    r = rng.random()
    if slow or r < 0.7:
        return rng.randrange(0, 8 if slow else 16)
    return rng.randrange(16, 64) if r < 0.9 else rng.randrange(64, 256)


def _audc(rng: random.Random, distortion: int) -> int:
    vol_only = 0x10 if rng.random() < 0.125 else 0
    return distortion << 5 | vol_only | rng.randrange(1, 16)


def _segment(s: Script, rng: random.Random, seg: int, audctl: int) -> None:
    s.w(AUDCTL, audctl)
    slow = bool(audctl & 1)
    for ch in range(4):
        joined_hi = (ch == 1 and audctl & 0x10) or (ch == 3 and audctl & 0x08)
        s.w(2 * ch, rng.randrange(0, 2) if joined_hi else _audf(rng, slow))
        s.w(2 * ch + 1, _audc(rng, (seg + 3 * ch) % 8))
    if rng.random() < 0.5:
        s.w(STIMER, rng.randrange(256))
    left = SEGMENT_CYCLES
    while left > 0:
        n = min(left, rng.randrange(150, 900))
        s.run(n)
        left -= n
        ch = rng.randrange(4)
        if rng.random() < 0.5:
            s.w(2 * ch, _audf(rng, slow))
        else:
            s.w(2 * ch + 1, _audc(rng, rng.randrange(8)))
    if seg % 16 == 15:
        s.w(SKCTL, 0)  # init mode: polys and bases held, 1.79 MHz channels run on
        s.run(rng.randrange(100, 400))
        s.w(SKCTL, 3)


def make_script(seed: int) -> Script:
    rng = random.Random(seed)
    s = Script()
    s.run(50)  # power-up: init mode, everything 0
    s.w(SKCTL, 3)
    order = list(range(256))
    rng.shuffle(order)
    for seg, audctl in enumerate(order):
        _segment(s, rng, seg, audctl)
    return s


def short_script(seed: int, cycles: int) -> Script:
    """A prefix of make_script(seed) of about `cycles` machine cycles."""
    full, s = make_script(seed), Script()
    for line in full.lines:
        if s.cycles >= cycles:
            break
        s.lines.append(line)
        if line.startswith("run"):
            s.cycles += int(line.split()[1])
    return s
