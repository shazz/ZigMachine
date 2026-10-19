#!/usr/bin/env python3
"""Reference model for DMA Intro 2 (DMA / Larcociel), reading the CART assets.

This is the dev-side twin of apps/larcociel2_headless.mjs: it composes a frame
exactly as the Go production (github.com/olivierh59500/go-larcociel2) and the Zig
cart do, from the ripped files under apps/zig/assets/screens/larcociel2/, so the
extraction can be proven against the Go's own captured PNGs.

Layout it reproduces (internal/demo/game.go's palette shader):
  i = background index (one of 0/4/8/12);  ball.a>0 -> i = (i/4)*4 + ball
  text.a>0 -> i = i%8 + 8
  i==8 && y<16 -> raster[y/2];  i==4 && 49<=y<93 -> raster[9+(y-49)/4]; else palette[i]

The balls are six slot sprites projected from the accelerating trail clock
(geometry.ProjectWordPoint), the text is DCK's scrolling slice stream over the
font atlas (36 eight-pixel slots at x=16+8i), and the raster is a real per-line
palette rewrite for entries 4 and 8.

Usage:  python3 tools/larcociel2/larco_model.py [--ref DIR] [--frames 0..1200]
"""
from __future__ import annotations
import argparse, struct
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
ASSETS = REPO / "apps/zig/assets/screens/larcociel2"

BAND_TOP, BAND_ROWS = 143, 57
BAND_FRAMES = 36


def rgbw(w): return ((w >> 8 & 7) * 34, (w >> 4 & 7) * 34, (w & 7) * 34)


class Model:
    def __init__(self, assets=ASSETS):
        a = Path(assets)
        self.bg_static = (a / "bg-static.bin").read_bytes()
        self.bg_band = (a / "bg-band.bin").read_bytes()
        self.balls = (a / "balls.bin").read_bytes()
        self.font = (a / "font.bin").read_bytes()
        pal = (a / "palette.bin").read_bytes()
        self.pal = [rgbw(struct.unpack(">H", pal[i * 2:i * 2 + 2])[0]) for i in range(16)]
        rast = (a / "raster.bin").read_bytes()
        self.rast = [rgbw(struct.unpack(">H", rast[i * 2:i * 2 + 2])[0]) for i in range(len(rast) // 2)]
        self.msg = (a / "message.txt").read_bytes()
        self.order = (a / "font-order.txt").read_bytes()
        self.init_motion = (a / "initial-motion.bin").read_bytes()
        self.init_history = (a / "initial-history.bin").read_bytes()
        self._ym = None

    # ---- 2-bit / 1-bit readers (the cart's own packing) --------------------
    @staticmethod
    def p2(buf, p): return (buf[p >> 2] >> (2 * (p & 3))) & 3
    @staticmethod
    def p1(buf, p): return (buf[p >> 3] >> (7 - (p & 7))) & 1

    def bg2(self, frame, y, x):
        """Palette index/4 (0..3) at (x,y) for background `frame`."""
        if y < BAND_TOP:
            return self.p2(self.bg_static, y * 320 + x)
        return self.p2(self.bg_band, frame * (BAND_ROWS * 320) + (y - BAND_TOP) * 320 + x)

    def ball_shade(self, k, y, x):
        return self.p2(self.balls, k * 1024 + y * 32 + x)

    def font_bit(self, g, y, x):
        return self.p1(self.font, g * 512 + y * 32 + x)

    # ---- the trail clock (internal/source/clock.go; int16 wraps) ----------
    def new_clock(self):
        m = self.init_motion
        w = lambda a: struct.unpack(">h", m[a:a + 2])[0]
        return {"Tick": 0, "Counter": w(18),
                "Velocity": [w(0), w(2), w(4)], "Acceleration": [w(6), w(8), w(10)],
                "Position": [w(12), w(14), w(16)],
                "History": [[struct.unpack(">h", self.init_history[i * 6 + j * 2:i * 6 + j * 2 + 2])[0]
                             for j in range(3)] for i in range(66)]}

    @staticmethod
    def _w16(x): return ((x + 32768) & 0xFFFF) - 32768

    def step_clock(self, c):
        c["History"] = c["History"][1:66] + [[0, 0, 0]]
        for j in range(3):
            c["Position"][j] = self._w16(c["Position"][j] + c["Velocity"][j])
        c["History"][65] = list(c["Position"])
        c["Counter"] += 1
        if c["Counter"] == 3:
            c["Counter"] = 0
            for j in range(3):
                c["Velocity"][j] = self._w16(c["Velocity"][j] + c["Acceleration"][j])
            if c["Velocity"][0] in (10, -10): c["Acceleration"][0] = self._w16(-c["Acceleration"][0])
            if c["Velocity"][1] in (7, -7): c["Acceleration"][1] = self._w16(-c["Acceleration"][1])
            if c["Velocity"][2] in (12, -12): c["Acceleration"][2] = self._w16(-c["Acceleration"][2])
        c["Tick"] += 1

    # ---- the projection (geometry.ProjectWordPoint) -----------------------
    @staticmethod
    def project(hx, hy, hz):
        """(screen X, screen Y, ball image index, visible). pose scale 205, bias 205,
        center (160,80), KeepLow overflow, Hide on zero depth."""
        x = Model._w16(hx - 160); y = Model._w16(hy - 80)
        px = 205 * x; py = 205 * y
        depth = Model._w16(hz + 205)
        if depth == 0:
            return (0, 0, 0, False)
        def div(n):
            # Go int64 division truncates toward zero; on int16 overflow the
            # KeepLow policy returns the LOW word of the numerator.
            q = abs(n) // abs(depth)
            if (n < 0) != (depth < 0): q = -q
            return Model._w16(n & 0xFFFF) if (q < -32768 or q > 32767) else q
        a = div(px); b = div(py)
        return (Model._w16(a + 160), Model._w16(b + 80), max(0, min(15, hz >> 5)), True)

    def slots(self, clock):
        """The six projected ball slots in draw order."""
        out = []
        for i in range(6):
            p = clock["History"][i * 11]
            sx, sy, img, vis = self.project(p[0], p[1], p[2])
            out.append((sx, sy, img, vis))
        return out

    # ---- the scrolling slice stream (scrolling.SliceStream, 36 x 8px) -----
    def glyph_index(self, ch):
        i = self.order.find(bytes([ch]))
        return 30 if i < 0 else i

    def new_stream(self):
        return {"head": 0, "token": 0, "slice": 0,
                "slices": [[-1, 0] for _ in range(36)],
                "tokens": [self.glyph_index(c) for c in self.msg]}

    def step_stream(self, s):
        s["head"] = (s["head"] + 1) % 36
        tail = (s["head"] + 35) % 36
        s["slices"][tail] = [s["tokens"][s["token"]], s["slice"]]
        s["slice"] += 1
        if s["slice"] >= 4:
            s["slice"] = 0
            s["token"] = (s["token"] + 1) % len(s["tokens"])

    def slot(self, s, i):
        return s["slices"][(s["head"] + i) % 36]

    # ---- the composited window --------------------------------------------
    def render(self, tick, clock, stream):
        frame = (tick - 1 + BAND_FRAMES) % BAND_FRAMES
        body = {}
        for (bx, by, bi, vis) in self.slots(clock):
            if not vis:
                continue
            for yy in range(32):
                Y = by + yy
                if not (0 <= Y < 200):
                    continue
                for xx in range(32):
                    sh = self.ball_shade(bi, yy, xx)
                    if not sh:
                        continue
                    X = bx + xx
                    if 0 <= X < 320:
                        body[(X, Y)] = sh
        text = set()
        for i in range(36):
            g, sl = self.slot(stream, i)
            if g < 0:
                continue
            x0 = 16 + 8 * i
            for yy in range(16):
                for k in range(8):
                    if self.font_bit(g, yy, sl * 8 + k):
                        text.add((x0 + k, yy))
        return self._compose(frame, body, text)

    def render0(self):
        return self._compose(BAND_FRAMES - 1, {}, set())

    def _compose(self, frame, body, text):
        out = bytearray(320 * 200 * 3)
        pal, rast = self.pal, self.rast
        for y in range(200):
            for x in range(320):
                i = self.bg2(frame, y, x) * 4
                sh = body.get((x, y))
                if sh: i += sh
                if (x, y) in text: i = i % 8 + 8
                if i == 8 and y < 16: c = rast[y // 2]
                elif i == 4 and 49 <= y < 93: c = rast[9 + (y - 49) // 4]
                else: c = pal[i]
                o = (y * 320 + x) * 3
                out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2]
        return out


def ref_rgb(path):
    from PIL import Image
    return bytearray(Image.open(path).convert("RGB").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="/tmp/opencode/larco2_ref")
    ap.add_argument("--frames", default="0..1200")
    a = ap.parse_args()
    lo, _, hi = a.frames.partition("..")
    lo, hi = int(lo), int(hi)
    m = Model()
    clock = m.new_clock()
    stream = m.new_stream()
    worst = 0
    if lo == 0:
        ref = Path(a.ref) / "000000.png"
        if ref.exists():
            d = sum(1 for p, q in zip(m.render0(), ref_rgb(ref)) if p != q)
            worst = max(worst, d)
            if d: print(f"frame 0: {d} mismatching bytes")
    for n in range(1, hi):
        m.step_clock(clock)
        m.step_stream(stream)
        if n < lo:
            continue
        got = m.render(n, clock, stream)
        ref = Path(a.ref) / f"{n:06d}.png"
        if not ref.exists():
            continue
        want = ref_rgb(ref)
        d = sum(1 for p, q in zip(got, want) if p != q)
        worst = max(worst, d)
        if d: print(f"frame {n}: {d} mismatching bytes")
    print(f"frames {lo}..{hi - 1}: worst mismatch {worst} bytes")


if __name__ == "__main__":
    main()
