"""Randomised blitter scripts (the format tests/blitter_ref/blitter_ref.zig and
tests/tb/blitter_tb.cpp both read): register writes and `run`s, every op x every minterm
class x clipping edges x halftone x SRC_ABS x DESC x colour key, plus the edge cases the
spec names. Registers are written with a probability, so stale values from earlier ops
are part of the test; both sides see the same stale state."""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "gen"))
import memmap as mm

BLIT, FILL, LINE, TRI = mm.BLIT_CMD_BLIT, mm.BLIT_CMD_FILL, mm.BLIT_CMD_LINE, mm.BLIT_CMD_TRIANGLE
MINTERMS = [
    mm.MT_A,
    mm.MT_B,
    mm.MT_C,
    mm.MT_COOKIE,
    mm.MT_XOR_BC,
    mm.MT_OR_BC,
    mm.MT_CLEAR,
    mm.MT_SET,
    0xEA,
    0x3C,
    0x96,
    0x80,
]
COLORS = [0, 1, 2, 0x55, 0xAA, 0xFF, 0x0F, 0xF0]
CLIP, DESC = mm.CON_CLIP_EN, mm.CON_DESC
PLANE = 0x1100  # OFF_VRAM: where the framebuffers live
WINDOWS = [
    (mm.CART_RAM_BASE, mm.CART_RAM_TOP),
    (mm.HW_VIDEO_BASE, mm.HW_VIDEO_BASE + mm.REGION_BYTES),
    (mm.ROM_RAM_BASE, mm.ROM_RAM_TOP),
]


class Script:
    def __init__(self, seed: int) -> None:
        self.r = random.Random(seed)
        self.lines = [f"seed {seed}"]
        self.runs = 0
        self.reg: dict[int, int] = {}
        self.cmd = 0

    def w(self, size: int, off: int, v: int, p: float = 1.0) -> None:
        if self.r.random() < p:
            for k in range(size // 8):  # the register file by byte, as the block holds it
                self.reg[off + k] = (v >> (8 * k)) & 0xFF
            self.lines.append(f"w{size} {off:#x} {v & ((1 << size) - 1):#x}")

    def pick(self, *a: int) -> int:
        return self.r.choice(a)

    def common(self, cmd: int, mt: int, con: int, con2: int) -> None:
        r = self.r
        stride = r.choice([320] * 8 + [400] * 5 + [64, 1000, 256])
        base = PLANE + r.choice([0, 64000, 128000, 0x40000, r.randrange(0, 0x100000, 16)])
        self.w(8, mm.BLIT_MINTERM, mt, 0.9)
        self.w(8, mm.BLIT_CON, con | r.choice([0, 0, 0, mm.CON_IFE | mm.CON_EFE]), 0.95)
        self.w(8, mm.BLIT_CON2, con2, 0.95)
        self.w(8, mm.BLIT_COLOR, r.choice(COLORS + [r.randrange(256)]), 0.9)
        self.w(8, mm.BLIT_BG_COLOR, r.choice(COLORS + [r.randrange(256)]), 0.9)
        self.w(8, mm.BLIT_COLOR_KEY, r.choice(COLORS), 0.9)
        self.w(32, mm.BLIT_D_BASE, base, 0.95)
        self.w(16, mm.BLIT_D_STRIDE, stride, 0.95)
        self.clip()
        self.halftone()
        self.cmd = cmd

    def clip(self) -> None:
        r = self.r
        sane = r.random() < 0.8
        self.w(16, mm.BLIT_CLIP_X, r.randrange(0, 150) if sane else r.choice([0, 319, 399, r.randrange(500)]), 0.9)
        self.w(16, mm.BLIT_CLIP_Y, r.randrange(0, 100) if sane else r.choice([0, 199, 279, r.randrange(400)]), 0.9)
        self.w(16, mm.BLIT_CLIP_W, r.randrange(40, 300) if sane else r.choice([0, 1, 1000, r.randrange(500)]), 0.9)
        self.w(16, mm.BLIT_CLIP_H, r.randrange(30, 200) if sane else r.choice([0, 1, 1000, r.randrange(300)]), 0.9)

    def halftone(self) -> None:
        r = self.r
        kind = r.choice(["keep", "zero", "rand", "ramp", "checker"])
        if kind == "keep":
            return
        for i in range(16):
            v = {"zero": 0, "rand": r.randrange(65536), "ramp": (1 << (i + 1)) - 1, "checker": 0xAAAA >> (i & 1)}[kind]
            self.w(16, mm.BLIT_HALFTONE + 2 * i, v)

    def coord(self, lo: int, hi: int) -> int:
        """Mostly on the plane (hi is its size), sometimes at an edge or off it."""
        r = self.r
        return r.choice([r.randint(0, hi - 1)] * 6 + [r.randint(lo, hi + 40), 0, -1, hi - 1, hi])

    def xy(self) -> tuple[int, int]:
        ds = self.get(mm.BLIT_D_STRIDE) or 320
        if self.get(mm.BLIT_CON, 8) & mm.CON_CLIP_EN and self.r.random() < 0.7:  # around the clip rect
            cx, cy = self.get(mm.BLIT_CLIP_X), self.get(mm.BLIT_CLIP_Y)
            return self.r.randint(cx - 12, cx + self.get(mm.BLIT_CLIP_W) + 8), self.r.randint(
                cy - 12, cy + self.get(mm.BLIT_CLIP_H) + 8
            )
        return self.coord(-60, ds), self.coord(-60, 280 if ds == 400 else 200)

    def size(self) -> tuple[int, int]:
        r = self.r
        return r.choice(
            [(0, 4), (5, 0), (1, 1)]
            + [(r.randint(1, 40), r.randint(1, 40)) for _ in range(6)]
            + [(r.randint(1, 330), r.randint(1, 210)) for _ in range(3)]
        )

    def run(self) -> None:
        self.lines.append(f"run {self.cmd}")
        self.runs += 1

    def get(self, off: int, size: int = 16, signed: bool = False) -> int:
        v = sum(self.reg.get(off + k, 0) << (8 * k) for k in range(size // 8))
        return v - (1 << size) if signed and v >> (size - 1) else v

    def box(self, x0: int, y0: int, x1: int, y1: int) -> tuple[int, int, int, int]:
        """[x0,x1) x [y0,y1) cut to the clip, as the machine does."""
        ds = self.get(mm.BLIT_D_STRIDE)
        cx0, cy0, cx1, cy1 = 0, 0, ds, 280 if ds == 400 else 200
        if self.get(mm.BLIT_CON, 8) & mm.CON_CLIP_EN:
            cx, cy = self.get(mm.BLIT_CLIP_X), self.get(mm.BLIT_CLIP_Y)
            cx0, cy0 = cx, cy
            cx1, cy1 = min(cx1, cx + self.get(mm.BLIT_CLIP_W)), min(cy1, cy + self.get(mm.BLIT_CLIP_H))
        return max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)

    def boundary(self, x0: int, y0: int, x1: int, y1: int) -> None:
        """Put D_BASE so the last byte the op reaches is just inside / on / past the region."""
        ex0, ey0, ex1, ey1 = self.box(x0, y0, x1, y1)
        if ex1 > ex0 and ey1 > ey0 and self.r.random() < 0.15:
            base = mm.REGION_BYTES - ((ey1 - 1) * self.get(mm.BLIT_D_STRIDE) + ex1) + self.pick(-1, 0, 1)
            self.w(32, mm.BLIT_D_BASE, max(base, 0))


def regs(**kw: int) -> dict[str, int]:
    return kw


FIELDS = {  # name -> (bits, register offset)
    "mt": (8, mm.BLIT_MINTERM),
    "con": (8, mm.BLIT_CON),
    "con2": (8, mm.BLIT_CON2),
    "color": (8, mm.BLIT_COLOR),
    "bg": (8, mm.BLIT_BG_COLOR),
    "key": (8, mm.BLIT_COLOR_KEY),
    "a": (32, mm.BLIT_A_BASE),
    "as_": (16, mm.BLIT_A_STRIDE),
    "b": (32, mm.BLIT_B_BASE),
    "bs": (16, mm.BLIT_B_STRIDE),
    "d": (32, mm.BLIT_D_BASE),
    "ds": (16, mm.BLIT_D_STRIDE),
    "w": (16, mm.BLIT_W),
    "h": (16, mm.BLIT_H),
    "x0": (16, mm.BLIT_X0),
    "y0": (16, mm.BLIT_Y0),
    "x1": (16, mm.BLIT_X1),
    "y1": (16, mm.BLIT_Y1),
    "x2": (16, mm.BLIT_X2),
    "y2": (16, mm.BLIT_Y2),
    "cx": (16, mm.BLIT_CLIP_X),
    "cy": (16, mm.BLIT_CLIP_Y),
    "cw": (16, mm.BLIT_CLIP_W),
    "ch": (16, mm.BLIT_CLIP_H),
}


def do(s: Script, cmd: int, **kw: int) -> None:
    for name, v in kw.items():
        bits, off = FIELDS[name]
        s.w(bits, off, v)
    s.cmd = cmd
    s.run()


def halftone(s: Script, rows: list[int]) -> None:
    for i, v in enumerate(rows):
        s.w(16, mm.BLIT_HALFTONE + 2 * i, v)
