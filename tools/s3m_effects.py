"""ScreamTracker 3 effects as FastTracker 2 effects, one cell at a time (s3m2xm.py).

ST3 letters (A=1 .. Z=26) become XM effect numbers (0..0x23). An effect the XM
format has no equivalent for is dropped and counted, never approximated
silently: the caller reports the counts. ST3's shared effect memory (a 00
parameter reuses the last non-zero one of D/E/F/I/J/K/L/Q/R/S on that channel)
is resolved here into explicit parameters, because XM keeps a memory per effect.
"""
from __future__ import annotations

from collections import Counter

SHARED = set("DEFIJKLQRS")  # the ST3 letters that share one parameter memory
XM_X = 0x21  # XM's X: extra-fine portamento (X1x up, X2x down)


def letter(eff: int) -> str:
    return chr(64 + eff) if 1 <= eff <= 26 else ""


class EffectMapper:
    """Converts cells for one song; `memory[track]` is ST3's shared parameter."""

    def __init__(self, order_map: dict[int, int]) -> None:
        self.order_map = order_map  # raw S3M order index -> XM order index (B)
        self.memory: dict[int, int] = {}
        self.dropped: Counter[str] = Counter()

    def convert(self, track: int, eff: int, param: int) -> tuple[int, int]:
        """The XM (effect, parameter) for an S3M one; (0, 0) when there is none."""
        name = letter(eff)
        if not name:
            return 0, 0
        if name in SHARED:
            param = param or self.memory.get(track, 0)
            self.memory[track] = param
        out = self._map(name, param)
        if out is None:
            self.dropped[f"{name}{param >> 4:X}" if name == "S" else name] += 1
            return 0, 0
        return out

    def _map(self, name: str, p: int) -> tuple[int, int] | None:
        simple = {"G": 3, "H": 4, "J": 0, "K": 6, "L": 5, "O": 9, "R": 7}
        if name in simple:
            return simple[name], p
        if name == "A":
            return (0xF, min(p, 0x1F)) if p else None
        if name == "T":
            return (0xF, p) if p >= 0x20 else None
        if name == "B":
            return 0xB, self.order_map.get(p, 0)
        if name == "C":
            return 0xD, p  # both store the row as two decimal digits
        if name == "V":
            return 0x10, min(p, 64)
        if name == "Q":
            return 0x1B, p
        if name == "D":
            return volume_slide(p)
        if name in "EF":
            return porta(name, p)
        if name == "S":
            return special(p)
        return None


def volume_slide(p: int) -> tuple[int, int]:
    """Dx0 up, D0y down, DxF fine up, DFy fine down (DFF is fine up F, as ST3)."""
    x, y = p >> 4, p & 0xF
    if y == 0xF and x:
        return 0xE, 0xA0 | x
    if x == 0xF and y:
        return 0xE, 0xB0 | y
    return 0xA, (x << 4) if x else y


def porta(name: str, p: int) -> tuple[int, int]:
    """Exx/Fxx slide down/up; xF? is fine (E1x/E2x), xE? extra fine (X1x/X2x)."""
    up = name == "F"
    if p >= 0xF0:
        return 0xE, (0x10 if up else 0x20) | (p & 0xF)
    if p >= 0xE0:
        return XM_X, (0x10 if up else 0x20) | (p & 0xF)
    return (1 if up else 2), p


def special(p: int) -> tuple[int, int] | None:
    """The Sxy commands XM has under E: loop, delay, cut, pattern delay, finetune."""
    xm_e = {0x2: 0x5, 0xB: 0x6, 0xC: 0xC, 0xD: 0xD, 0xE: 0xE}
    x = p >> 4
    if x not in xm_e:
        return None
    return 0xE, (xm_e[x] << 4) | (p & 0xF)
