#!/usr/bin/env python3
"""Reference model for DMA Intro 5 (DMA / Larcociel), reading the CART assets.

This is the dev-side twin of apps/larcociel5_headless.mjs: it composes a frame
exactly as the Go production (github.com/olivierh59500/go-larcociel5) and the Zig
cart do, from the ripped files under apps/zig/assets/screens/larcociel5/, so the
extraction can be proven against the Go's own captured PNGs.

Layout it reproduces (internal/demo/game.go's palette shader):
  i = background index;  ribbon.a>0 -> i =(i&~3)|ribbon;  y<32 -> i = i%4 | bat4
  y>=100 && i>0 -> colourBank[y-100][i];  i==4 && y<64 -> raster[y];  else palette[i]
The colour bank is DCK's perspective sampling of the 272-row font-colour stencil.

Usage:  python3 tools/larcociel5/larco_model.py [--ref DIR] [--frames 0..1199]
"""
from __future__ import annotations
import argparse, struct
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
ASSETS = REPO / "apps/zig/assets/screens/larcociel5"
GBAR = ord('|')

def rgbw(w): return ((w >> 8 & 7) * 34, (w >> 4 & 7) * 34, (w & 7) * 34)

class Model:
    def __init__(self, assets=ASSETS):
        a = Path(assets)
        self.bg = (a / "bg.idx").read_bytes()
        self.ribbon = (a / "ribbon.bin").read_bytes()
        self.bats = (a / "bats.bin").read_bytes()
        pal = (a / "palette.bin").read_bytes()
        self.pal = [rgbw(struct.unpack(">H", pal[i*2:i*2+2])[0]) for i in range(16)]
        rast = (a / "raster.bin").read_bytes()
        self.rast = [rgbw(struct.unpack(">H", rast[i*2:i*2+2])[0]) if i < len(rast)//2 else rgbw(0x700)
                     for i in range(64)]
        self.fc = (a / "font-colors.bin").read_bytes()
        self.msg = (a / "message.txt").read_bytes()
        seq = (a / "music.seq").read_bytes()
        self.ym_frames = struct.unpack("<I", seq[0:4])[0]
        self.ym = seq[4:]
        self._ym_offsets = None
        # the initial clock state (the Go's assets/original binaries)
        m = (a / "initial-motion.bin").read_bytes() if (a / "initial-motion.bin").exists() else None
        self.init_history = (a / "initial-history.bin").read_bytes()
        self.init_motion = m or bytes.fromhex("0006ffff00620003ffff0014")

    def fontword(self, glyph, row, col):
        o = (glyph*255 + row*15 + col)*2
        return struct.unpack(">H", self.fc[o:o+2])[0]

    # ---- the ribbon clock (internal/source/clock.go; int16 wraps) ----
    def new_clock(self):
        m = self.init_motion
        w = lambda at: struct.unpack(">h", m[at:at+2])[0]
        c = {"VX": w(0), "AX": w(2), "X": w(4), "VY": w(6), "AY": w(8), "Y": w(10),
             "Hold": 62, "Tick": 0, "Counter": 0,
             "History": [struct.unpack(">h", self.init_history[i*2:i*2+2])[0] for i in range(50)]}
        return c

    @staticmethod
    def _w16(x): return ((x + 32768) & 0xFFFF) - 32768

    def step_clock(self, c):
        c["Tick"] += 1
        if c["Tick"] % 320 == 0: c["Hold"] = 61
        c["History"] = c["History"][1:50] + [0]
        if c["Hold"] > 0:
            c["Hold"] -= 1
        else:
            c["X"] = self._w16(c["X"] + c["VX"]); c["Y"] = self._w16(c["Y"] + c["VY"]); c["Counter"] += 1
            if c["Counter"] == 5:
                c["Counter"] = 0
                c["VX"] = self._w16(c["VX"] + c["AX"]); c["VY"] = self._w16(c["VY"] + c["AY"])
                if c["VX"] == 6 or c["VX"] == -6: c["AX"] = self._w16(-c["AX"])
                if c["VY"] == 3 or c["VY"] == -3: c["AY"] = self._w16(-c["AY"])
        c["History"][49] = c["X"]

    # ---- the YM delta stream ----
    def ym_frame_regs(self, idx):
        if self._ym_offsets is None:
            offs = []
            o = 0
            for _ in range(self.ym_frames):
                mask = struct.unpack("<H", self.ym[o:o+2])[0]; o += 2
                offs.append((o, mask)); o += bin(mask).count("1")
            self._ym_offsets = offs
        regs = [0]*14
        for f in range(idx+1):
            o, mask = self._ym_offsets[f]
            for r in range(14):
                if mask & (1 << r):
                    regs[r] = self.ym[o]; o += 1
        return regs

    def glyph_index(self, ch):
        if ch == 32: return 0
        if ch == 46: return 27
        if ch == 44: return 28
        if ch == 39: return 29
        return max(0, min(26, ch-64))

    # ---- the colour bank: DCK's vertical glyph window -> 272x15 stencil -> 100 x 16 ----
    def build_colors(self, tick):
        position = max(0, tick-1)
        current = position // 17 % len(self.msg)
        off = position % 17
        stencil = [None]*272
        for slot in range(16):
            ch = self.msg[current+slot] if current+slot < len(self.msg) else 32
            g = self.glyph_index(ch)
            top = slot*17 - off
            for row in range(17):
                y = top + row
                if 0 <= y < 272:
                    stencil[y] = [rgbw(self.fontword(g, row, col)) for col in range(15)]
        colors = [[(0, 0, 0)]*16 for _ in range(100)]
        out = 0; phase = 0; step = 20; row = 0
        while out < 100 and row < 272:
            phase += step
            if phase < 80:
                row += 1; continue
            phase -= 80; step += 1
            srow = stencil[row]
            for col in range(15): colors[out][col+1] = srow[col]
            out += 1; row += 1
        return colors

    def render(self, tick, clock, ymframe, with_meters=True):
        colors = self.build_colors(tick)
        body = {}
        for r in range(50):
            X = clock["History"][r]; Y = clock["Y"] + r
            if not (0 <= Y < 200): continue
            for x in range(112):
                v = self.ribbon[r*112+x]
                if v:
                    dx = x + X
                    if 0 <= dx < 320: body[(dx, Y)] = v & 3
        if with_meters:
            regs = self.ym_frame_regs(ymframe)
            vol = [max(1, regs[8] & 15), max(1, regs[10] & 15), max(1, regs[9] & 15)]
        else:
            vol = [1, 1, 1]
        masks = [self.bats[(15-vol[m])*256:(16-vol[m])*256] for m in range(3)]
        def batbit(m, x, y):
            o = y*64 + x
            return (masks[m][o >> 3] >> (7 - (o & 7))) & 1
        out = bytearray(320*200*3)
        bg = self.bg; pal = self.pal; rast = self.rast
        for y in range(200):
            base = y*320
            for x in range(320):
                i = bg[base+x]
                bv = body.get((x, y))
                if bv is not None: i = (i & ~3) | bv
                if y < 32:
                    rx = x % 128
                    if rx < 64 and batbit(x >> 7, rx, y): i |= 4
                if y >= 100 and i > 0: c = colors[y-100][i]
                elif i == 4 and y < 64: c = rast[y]
                else: c = pal[i]
                o = (base+x)*3
                out[o] = c[0]; out[o+1] = c[1]; out[o+2] = c[2]
        return out

    def render0(self):
        """The Go's frame 0: Update never ran (empty body, bats, colour bank)."""
        out = bytearray(320*200*3)
        for y in range(200):
            for x in range(320):
                i = self.bg[y*320+x]
                if y < 32: i %= 4
                if y >= 100 and i > 0: c = (0, 0, 0)
                elif i == 4 and y < 64: c = self.rast[y]
                else: c = self.pal[i]
                o = (y*320+x)*3
                out[o] = c[0]; out[o+1] = c[1]; out[o+2] = c[2]
        return out


def ref_rgb(path):
    from PIL import Image
    return bytearray(Image.open(path).convert("RGB").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="/tmp/opencode/larco_ref")
    ap.add_argument("--frames", default="0..1200")
    a = ap.parse_args()
    lo, _, hi = a.frames.partition("..")
    lo, hi = int(lo), int(hi)
    m = Model()
    clock = m.new_clock()
    worst = 0
    if lo == 0:
        ref = Path(a.ref) / "000000.png"
        if ref.exists():
            d = sum(1 for p, q in zip(m.render0(), ref_rgb(ref)) if p != q)
            worst = max(worst, d)
            if d: print(f"frame 0: {d} mismatching bytes")
    for n in range(1, hi):
        m.step_clock(clock)  # frame n is the state AFTER n steps
        if n < lo:
            continue
        got = m.render(n, clock, n - 1)
        ref = Path(a.ref) / f"{n:06d}.png"
        if not ref.exists():
            continue
        want = ref_rgb(ref)
        d = sum(1 for p, q in zip(got, want) if p != q)
        worst = max(worst, d)
        if d: print(f"frame {n}: {d} mismatching bytes")
    print(f"frames {lo}..{hi-1}: worst mismatch {worst} bytes")


if __name__ == "__main__":
    main()
