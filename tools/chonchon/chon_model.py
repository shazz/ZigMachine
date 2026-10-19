#!/usr/bin/env python3
"""Reference model for CHONCHON (Chon-Chon / DMA), the olivierh59500 Go/Ebitengine
re-creation github.com/olivierh59500/go-chonchon, reading the CART assets under
apps/zig/assets/screens/chonchon/.

This is the dev-side twin of apps/chonchon_headless.mjs. It reproduces, byte for
byte, the Go production's own captured frames: the native 4-plane ST screen that
internal/source/clock.go builds (background + 100 authored star paths + the
two-bank ring scroller fed by the Huffman-unpacked font), the three YM-volume
music meters overlaid into plane 3, the 63-row warped chrome logo, the static
palette and the 28-word raster the final shader paints on rows 144..199.

The Go's internal/demo/game.go, verbatim, is exactly this decomposition:

  Screen  <- Background                       (clock.Step)
  Screen  <- stars | scroll ring | logo rows  (clock.Step)
  Screen  <- Screen | meters                  (Update, plane-3 mask off meter-raw)
  i       <- 4-plane decode of Screen         (Pixels)
  i       <- logo-bank index where opaque     (ImageSlots over the index image)
  colour  <- i>=8 && y>=144 ? raster[(y-144)/2] : palette[i]

Usage:  python3 tools/chonchon/chon_model.py [--ref DIR] [--frames N]
"""
from __future__ import annotations
import argparse, struct, sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent.parent
ASSETS = REPO / "apps/zig/assets/screens/chonchon"


def rgbw(w):
    return ((w >> 8 & 7) * 34, (w >> 4 & 7) * 34, (w & 7) * 34)


def be16(b, o):
    return (b[o] << 8) | b[o + 1]


def be32(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


def s16(v):
    return v - 65536 if v >= 32768 else v


class YM:
    """The music.seq delta stream: u32 frame count then per frame a u16 mask of
    the registers 0..13 that changed and their new values in ascending order."""

    def __init__(self, seq: bytes):
        self.frames = struct.unpack("<I", seq[0:4])[0]
        self.data = seq[4:]
        self.off = []
        o = 0
        for _ in range(self.frames):
            mask = self.data[o] | (self.data[o + 1] << 8)
            o += 2
            self.off.append((o, mask))
            o += bin(mask).count("1")
        # Registers persist between writes, so expand the delta stream into the
        # full register file once (10650 * 14 bytes).
        self.state = []
        cur = [0] * 14
        for o, mask in self.off:
            for k in range(14):
                if mask & (1 << k):
                    cur[k] = self.data[o]
                    o += 1
            self.state.append(list(cur))

    def at(self, f):
        """Register values after frame f (0-based)."""
        return self.state[f]


class Model:
    def __init__(self, assets=ASSETS):
        a = Path(assets)
        self.bg = (a / "background.bin").read_bytes()
        self.font = (a / "font-source.bin").read_bytes()
        self.path = (a / "logo-path.bin").read_bytes()
        self.ys = (a / "logo-y.bin").read_bytes()
        self.wave = (a / "scroll-y.bin").read_bytes()
        self.msg = (a / "message.bin").read_bytes()
        self.stars = (a / "star-paths.bin").read_bytes()
        self.index = (a / "star-index.bin").read_bytes()
        self.logo = (a / "logo.idx").read_bytes()
        pal = (a / "palette.bin").read_bytes()
        self.pal = [rgbw(be16(pal, i * 2)) for i in range(16)]
        rast = (a / "raster.bin").read_bytes()
        self.rast = [rgbw(be16(rast, i * 2)) for i in range(28)]
        self.curve = (a / "volume-curve.bin").read_bytes()
        self.meter_raw = (a / "meter-raw.bin").read_bytes()
        self.ym = YM((a / "music.seq").read_bytes())
        assert len(self.bg) == 32000

    # ---- internal/source/clock.go, statement for statement ------------------
    def new(self, want_meter=False, want_logo=True):
        c = {
            "Tick": 0, "LogoPhase": 0, "LogoYPhase": 0, "LogoY": 0, "ScrollPhase": 0,
            "MessageCursor": 0, "Counter": 0,
            "Ring": [bytearray(3432), bytearray(3432)],
            "Write": [2808, 2808], "Read": [0, 0],
            "Screen": bytearray(32000),
            "StarBase": [0] * 100, "StarCursor": [0] * 100,
        }
        for i in range(100):
            c["StarBase"][i] = be32(self.index, i * 6) - 0x1B018 - 0x1CC88
            c["StarCursor"][i] = be16(self.index, i * 6 + 4)
        self.step(c)
        self.step(c)
        c["Tick"] = 0
        return c

    def logo_row(self, c, row):
        p = c["LogoPhase"] + row * 6
        offset = be16(self.path, p)
        phase = be32(self.path, p + 2) // 72
        return offset // 8 * 16, phase, c["LogoY"] + row

    def step(self, c):
        c["Tick"] += 1
        c["Screen"][:] = self.bg
        c["LogoPhase"] += 12
        if s16(be16(self.path, c["LogoPhase"] + 63 * 6)) < 0:
            c["LogoPhase"] = 0
        c["LogoYPhase"] += 1
        if c["LogoYPhase"] * 2 >= len(self.ys) or s16(be16(self.ys, c["LogoYPhase"] * 2)) < 0:
            c["LogoYPhase"] = 0
        c["LogoY"] = be16(self.ys, c["LogoYPhase"] * 2) // 160
        for i in range(100):
            p = c["StarBase"][i] + c["StarCursor"][i] + 6
            if p + 6 > len(self.stars) or be16(self.stars, p) == 0:
                c["StarCursor"][i] = 0
                p = c["StarBase"][i]
            else:
                c["StarCursor"][i] += 6
            off = be16(self.stars, p)
            if off + 4 <= len(c["Screen"]):
                v = be32(c["Screen"], off) | be32(self.stars, p + 2)
                c["Screen"][off:off + 4] = struct.pack(">I", v)
        bank = (c["Tick"] - 1) % 2
        if bank == 0 and c["Counter"] == 0:
            if c["MessageCursor"] + 2 > len(self.msg) or s16(be16(self.msg, c["MessageCursor"])) < 0:
                c["MessageCursor"] = 0
            off = be16(self.msg, c["MessageCursor"])
            c["Write"][0] = (c["Write"][0] + 312) % 3432
            if off + 312 <= len(self.font):
                c["Ring"][0][c["Write"][0]:c["Write"][0] + 312] = self.font[off:off + 312]
        if bank == 1:
            c["Counter"] -= 1
            if c["Counter"] < 0:
                c["Counter"] = 1
                if c["MessageCursor"] + 2 > len(self.msg) or s16(be16(self.msg, c["MessageCursor"])) < 0:
                    c["MessageCursor"] = 0
                off = s16(be16(self.msg, c["MessageCursor"]))
                c["MessageCursor"] += 2
                c["Write"][1] = (c["Write"][1] + 312) % 3432
                packed = 0x18369 - 0xCE2A + off
                if packed >= 0 and packed + 312 <= len(self.font):
                    for row in range(26):
                        src = packed + row * 12
                        dst = c["Write"][1] + row * 6
                        for plane in range(3):
                            aa = (dst - 155 + plane * 2 + 3432) % 3432
                            c["Ring"][1][aa] = self.font[src + plane]
                        for j in range(6):
                            c["Ring"][1][(dst + j) % 3432] = self.font[src + 3 + j]
                        for plane in range(3):
                            c["Ring"][1][(dst + 156 + plane * 2) % 3432] = self.font[src + 9 + plane]
        c["ScrollPhase"] += 2
        if c["ScrollPhase"] * 2 >= len(self.wave) or s16(be16(self.wave, c["ScrollPhase"] * 2)) < 0:
            c["ScrollPhase"] = 0
        c["Read"][bank] = (c["Read"][bank] + 156) % 3432
        for col in range(18):
            p = c["ScrollPhase"] + col * 2
            while p >= len(self.wave) // 2 or s16(be16(self.wave, p * 2)) < 0:
                p = 0
            p2 = p + 1
            if p2 >= len(self.wave) // 2 or s16(be16(self.wave, p2 * 2)) < 0:
                p2 = 0
            y1 = be16(self.wave, p * 2) // 160
            y2 = be16(self.wave, p2 * 2) // 160
            for row in range(26):
                r = (c["Read"][bank] + col * 156 + row * 6) % 3432
                for plane in range(3):
                    aa = (y1 + row) * 160 + (col + 1) * 8 + plane * 2
                    bb = (y2 + row) * 160 + (col + 1) * 8 + plane * 2 + 1
                    if 0 <= aa < len(c["Screen"]):
                        c["Screen"][aa] = c["Ring"][bank][r + plane * 2]
                    if 0 <= bb < len(c["Screen"]):
                        c["Screen"][bb] = c["Ring"][bank][r + plane * 2 + 1]

    # ---- game.go Update: the three YM-volume meters into plane 3 ------------
    def apply_meter(self, c, regs):
        vol = [regs[8] & 15, regs[9] & 15, regs[10] & 15]
        for ch in range(3):
            height = self.curve[vol[ch]]
            if height == 0:
                continue
            x = 96 if ch == 0 else (144 if ch == 1 else 176)
            width = 32 if ch == 1 else 48
            source_x = x - 96
            for row in range(height + 1):
                if row >= 52:
                    break
                for dx in range(width):
                    p = (147 + row) * 160 + (x + dx) // 16 * 8 + 6
                    mask = 1 << (15 - (x + dx) % 16)
                    w = be16(c["Screen"], p)
                    q = source_x + dx
                    v = be16(self.meter_raw, row * 160 + q // 16 * 8)
                    if (v >> (15 - q % 16)) & 1:
                        w |= mask
                    c["Screen"][p:p + 2] = struct.pack(">H", w)

    # ---- Pixels + the logo slots + the final shader -------------------------
    def render(self, c, with_logo=True, with_meter=True):
        scr = c["Screen"]
        out = bytearray(320 * 200 * 3)
        logo = self.logo
        for y in range(200):
            base = y * 160
            for x in range(320):
                g = x // 16
                w0 = (scr[base + g * 8] << 8) | scr[base + g * 8 + 1]
                w1 = (scr[base + g * 8 + 2] << 8) | scr[base + g * 8 + 3]
                w2 = (scr[base + g * 8 + 4] << 8) | scr[base + g * 8 + 5]
                w3 = (scr[base + g * 8 + 6] << 8) | scr[base + g * 8 + 7]
                bit = 15 - (x % 16)
                i = ((w0 >> bit & 1) | (w1 >> bit & 1) << 1 |
                     (w2 >> bit & 1) << 2 | (w3 >> bit & 1) << 3)
                if y >= 144 and i >= 8:
                    col = self.rast[(y - 144) // 2]
                else:
                    col = self.pal[i]
                o = (y * 320 + x) * 3
                out[o] = col[0]
                out[o + 1] = col[1]
                out[o + 2] = col[2]
        if with_logo:
            for row in range(63):
                lx, phase, ly = self.logo_row(c, row)
                if ly < 0 or ly >= 200:
                    continue
                sr = (row * 17 + phase) * 96
                for dx in range(96):
                    i = logo[sr + dx]
                    if i == 0:
                        continue
                    px = lx + dx
                    if 0 <= px < 320:
                        if ly >= 144 and i >= 8:
                            col = self.rast[(ly - 144) // 2]
                        else:
                            col = self.pal[i]
                        o = (ly * 320 + px) * 3
                        out[o] = col[0]
                        out[o + 1] = col[1]
                        out[o + 2] = col[2]
        return out

    def render0(self, c):
        """The boot frame: NewGame never wrote `pixels`/drew the slots, so the
        index image is all zero -> palette[0] everywhere (black for this palette)."""
        return bytes(self.pal[0]) * (320 * 200)


def decode_png(buf):
    """Minimal PNG decoder (RGBA8/RGB8, non-interlaced) -- no PIL dependency."""
    import zlib
    assert buf.read(8) == b"\x89PNG\r\n\x1a\n"
    o = 8
    idat = []
    w = h = ct = 0
    while o + 8 <= len(buf):
        ln = int.from_bytes(buf[o:o + 4], "big")
        typ = buf[o + 4:o + 8]
        data = buf[o + 8:o + 8 + ln]
        if typ == b"IHDR":
            w = int.from_bytes(data[0:4], "big")
            h = int.from_bytes(data[4:8], "big")
            assert data[8] == 8 and data[12] == 0
            ct = data[9]
        elif typ == b"IDAT":
            idat.append(data)
        elif typ == b"IEND":
            break
        o += 12 + ln
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(b"".join(idat))
    stride = w * ch
    img = bytearray(h * stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        row = raw[p:p + stride]; p += stride
        cur = img[y * stride:(y + 1) * stride]
        prev = img[(y - 1) * stride:y * stride] if y else None
        for x in range(stride):
            a = cur[x - ch] if x >= ch else 0
            b = prev[x] if prev else 0
            cc = prev[x - ch] if (prev and x >= ch) else 0
            v = row[x]
            if f == 1:
                v = (v + a) & 255
            elif f == 2:
                v = (v + b) & 255
            elif f == 3:
                v = (v + ((a + b) >> 1)) & 255
            elif f == 4:
                pp = a + b - cc
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - cc)
                v = (v + (a if pa <= pb and pa <= pc else (b if pb <= pc else cc))) & 255
            elif f != 0:
                raise ValueError(f"PNG filter {f}")
            cur[x] = v
    rgb = bytearray(w * h * 3)
    for i in range(w * h):
        for k in range(3):
            rgb[i * 3 + k] = img[i * ch + k] if ct != 3 else img[i * ch + (k if k < 3 else 0)]
    return w, h, rgb


def ref_rgb(path):
    im = Image.open(path).convert("RGB")
    assert im.size == (320, 200), f"{path}: {im.size}"
    return im.tobytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="/tmp/opencode/chon_ref")
    ap.add_argument("--frames", type=int, default=1200)
    args = ap.parse_args()
    m = Model()
    c = m.new()
    worst = 0
    for n in range(args.frames):
        if n > 0:
            m.step(c)
            m.apply_meter(c, m.ym.at(n - 1))
            got = m.render(c, with_logo=True)
        else:
            got = m.render0(c)
        want = ref_rgb(Path(args.ref) / f"{n:06d}.png")
        d = sum(1 for p, q in zip(got, want) if p != q)
        if d:
            bad = next(i for i in range(len(want)) if got[i] != want[i])
            px = (bad // 3) % 320
            py = (bad // 3) // 320
            print(f"frame {n}: {d} bytes differ, first at ({px},{py}) got {tuple(got[bad:bad+3])} want {tuple(want[bad:bad+3])}", file=sys.stderr)
            sys.exit(1)
        worst = max(worst, 0)
    print(f"chonchon model reproduces all {args.frames} captured Go frames byte for byte")


if __name__ == "__main__":
    main()
