#!/usr/bin/env python3
"""Rip DMA Intro 2 (go-larcociel2) assets to the cart's raw form, and verify.

Source: /tmp/opencode/larcociel2  (github.com/olivierh59500/go-larcociel2).
Output: apps/zig/assets/screens/larcociel2/*  and a few Go frames under
tools/larcociel2/go_ref/ for the headless harness.

Everything the cart draws that is NOT generated (the music, the trail clock) is
an extraction of assets/original/:

  bg-static.bin      rows 0..142 of every background: 2-bit palette groups
                     (index/4) packed 4 pixels/byte, LSB pixel first. The
                     backgrounds only ever use indices 0/4/8/12, so the Go's
                     i/4 ball rule is exact on the stored 2 bits.
  bg-band.bin        36 frames x rows 143..199 (57 rows), same 2-bit packing. These rows
                     change every frame and are NOT a rotation of one another.
  balls.bin          16 x 32x32 2-bit sprites; 0 = transparent, 1..3 = shade
                     (the Go's ball.a and ball.r -> index 1..3).
  font.bin           31 glyphs x 32x16 1-bit alpha masks (font.png's alpha; the
                     Go's text rule reads only alpha). MSB pixel first.
  palette.bin / raster.bin / message.txt / font-order.txt
                     verbatim originals (the ST colour words, the stencil feed)
  initial-motion.bin / initial-history.bin
                     verbatim: the trail clock's seed and its 66-point history
  music.seq          the YM6 register stream as per-frame deltas (see ym.zig)

A source mismatch is a hard error; the extracted files are then re-rendered by
tools/larcociel2/larco_model.py and compared to every captured Go frame.
"""
from __future__ import annotations
import struct, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SRC = Path("/tmp/opencode/larcociel2")
OUT = REPO / "apps/zig/assets/screens/larcociel2"
GO_REF = Path("/tmp/opencode/larco2_ref")
REF_OUT = REPO / "tools/larcociel2/go_ref"

BAND_TOP, BAND_ROWS, BAND_FRAMES = 143, 57, 36

from PIL import Image


def rd(n): return (SRC / "assets/original" / n).read_bytes()


def pack2(vals):
    vals = list(vals)
    out = bytearray((len(vals) + 3) // 4)
    for i, v in enumerate(vals):
        out[i >> 2] |= (v & 3) << (2 * (i & 3))
    return bytes(out)


def pack1(bits):
    bits = list(bits)
    out = bytearray((len(bits) + 7) // 8)
    for i, b in enumerate(bits):
        if b: out[i >> 3] |= 1 << (7 - (i & 7))
    return bytes(out)


def index_of(r, name, x, y):
    i = (r * 15 + 127) // 255
    if abs(i * 17 - r) > 1:
        sys.exit(f"{name}: ({x},{y}) R {r} is not a palette index")
    return i


def load_bg(n):
    im = Image.open(SRC / "assets/original" / f"background-{n}.png").convert("RGBA")
    assert im.size == (320, 200), f"background-{n}: {im.size}"
    px = im.load()
    grid = [[0] * 320 for _ in range(200)]
    for y in range(200):
        for x in range(320):
            r, g, b, a = px[x, y]
            if a != 255: sys.exit(f"background-{n}: ({x},{y}) alpha {a}")
            i = index_of(r, f"background-{n}", x, y)
            if i not in (0, 4, 8, 12): sys.exit(f"background-{n}: ({x},{y}) index {i}")
            grid[y][x] = i
    return grid


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    bgs = [load_bg(n) for n in range(BAND_FRAMES)]
    # Rows above the band must be identical across every frame, or the split is wrong.
    for y in range(BAND_TOP):
        row = bgs[0][y]
        for n in range(1, BAND_FRAMES):
            if bgs[n][y] != row:
                sys.exit(f"background row {y} differs at frame {n}: not static")
    static = pack2(bgs[0][y][x] // 4 for y in range(BAND_TOP) for x in range(320))
    band = b"".join(pack2(bgs[n][y][x] // 4 for y in range(BAND_TOP, 200) for x in range(320))
                    for n in range(BAND_FRAMES))
    (OUT / "bg-static.bin").write_bytes(static)
    (OUT / "bg-band.bin").write_bytes(band)

    balls = bytearray()
    for k in range(16):
        im = Image.open(SRC / "assets/original" / f"ball-{k}.png").convert("RGBA")
        assert im.size == (32, 32), f"ball-{k}: {im.size}"
        px = im.load()
        vals = []
        for y in range(32):
            for x in range(32):
                r, g, b, a = px[x, y]
                if a not in (0, 255): sys.exit(f"ball-{k}: ({x},{y}) alpha {a}")
                i = index_of(r, f"ball-{k}", x, y)
                if a == 0:
                    if i != 0: sys.exit(f"ball-{k}: ({x},{y}) transparent index {i}")
                    vals.append(0)
                else:
                    if not 1 <= i <= 3: sys.exit(f"ball-{k}: ({x},{y}) shade {i}")
                    vals.append(i)
        balls += pack2(vals)
    (OUT / "balls.bin").write_bytes(bytes(balls))

    im = Image.open(SRC / "assets/original" / "font.png").convert("RGBA")
    assert im.size == (992, 16), f"font: {im.size}"
    px = im.load()
    bits = []
    for g in range(31):
        for y in range(16):
            for x in range(32):
                r, gg, b, a = px[g * 32 + x, y]
                if a not in (0, 255): sys.exit(f"font: glyph {g} ({x},{y}) alpha {a}")
                if a == 255 and index_of(r, "font", x, y) != 8:
                    sys.exit(f"font: glyph {g} ({x},{y}) opaque index {index_of(r, 'font', x, y)}")
                bits.append(1 if a else 0)
    (OUT / "font.bin").write_bytes(pack1(bits))

    for n in ["palette.bin", "raster.bin", "message.txt", "font-order.txt",
              "initial-motion.bin", "initial-history.bin"]:
        (OUT / n).write_bytes(rd(n))

    ym = rd("music.ym")
    frames = struct.unpack(">I", ym[12:16])[0]
    attr = struct.unpack(">I", ym[16:20])[0]
    if attr != 1: sys.exit(f"music.ym: unexpected attributes {attr}")
    data = len(ym) - 16 * frames  # three NUL-terminated strings then register-major data
    assert data > 0 and data + 16 * frames == len(ym), "music.ym: bad register data length"
    seq = bytearray(struct.pack("<I", frames))
    prev = [0] * 14
    for f in range(frames):
        mask = 0; vals = []
        for r in range(14):
            v = ym[data + r * frames + f]
            if f == 0 or v != prev[r]:
                mask |= 1 << r; vals.append(v)
            prev[r] = v
        seq += struct.pack("<H", mask); seq += bytes(vals)
    (OUT / "music.seq").write_bytes(bytes(seq))
    print(f"music.seq: {frames} frames -> {len(seq)} bytes ({(len(seq) - 4) / frames:.2f} B/frame)")

    sizes = {"bg-static.bin": 143 * 320 // 4, "bg-band.bin": 36 * 57 * 320 // 4,
             "balls.bin": 16 * 1024 // 4, "font.bin": 31 * 512 // 8,
             "palette.bin": 32, "raster.bin": 40, "message.txt": len(rd("message.txt")),
             "font-order.txt": len(rd("font-order.txt")),
             "initial-motion.bin": 20, "initial-history.bin": 396}
    for n, want in sizes.items():
        got = (OUT / n).stat().st_size
        assert got == want, f"{n}: {got} != {want}"
    print("ripped:", ", ".join(f"{n}={v}" for n, v in sizes.items()))

    if not GO_REF.is_dir():
        print(f"note: {GO_REF} absent; skipped the Go-frame comparison")
        return
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import larco_model
    lm = larco_model.Model(OUT)
    clock = lm.new_clock()
    stream = lm.new_stream()
    N = 1200
    worst = 0
    for n in range(N):
        if n > 0:
            lm.step_clock(clock)
            lm.step_stream(stream)
            got = lm.render(n, clock, stream)
        else:
            got = lm.render0()
        want = larco_model.ref_rgb(GO_REF / f"{n:06d}.png")
        d = sum(1 for p, q in zip(got, want) if p != q)
        worst = max(worst, d)
        if d: sys.exit(f"the extracted assets differ from the Go frame {n} by {d} bytes")
    print(f"the extracted assets reproduce all {N} captured Go frames byte for byte")
    REF_OUT.mkdir(parents=True, exist_ok=True)
    keep = [0, 1, 2, 10, 50, 100, 149, 200, 320, 500, 800, 1000, 1100, 1199]
    for n in keep:
        (REF_OUT / f"{n:06d}.png").write_bytes((GO_REF / f"{n:06d}.png").read_bytes())
    print(f"kept {len(keep)} Go frames under {REF_OUT.relative_to(REPO)}")


main()
