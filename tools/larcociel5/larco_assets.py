#!/usr/bin/env python3
"""Rip DMA Intro 5 (go-larcociel5) assets to the cart's raw form, and verify.

Source: /tmp/opencode/larcociel5  (github.com/olivierh59500/go-larcociel5).
Output: apps/zig/assets/screens/larcociel5/*  and a few Go frames under
tools/larcociel5/go_ref/ for the headless harness.

Everything the cart draws that is NOT generated (the music, the ribbon clock,
the perspective stencil) is an extraction of assets/original/:

  bg.idx           320x200 palette indices 0..15 (background.png's R = idx*17)
  ribbon.bin       112x50, a palette index 1..3 where alpha=1, 0 = transparent
  bats.bin         15 x 64x32 1-bit alpha masks (bat-*.png; every covered pixel
                   is R=68 => palette index 4, the shader's bat value)
  palette.bin / raster.bin / font-colors.bin / message.txt
                   verbatim originals (the ST colour words and the font bank)
  initial-motion.bin / initial-history.bin
                   verbatim: the ribbon clock's seed and its 50-row history
  music.seq        the YM6 register stream as per-frame deltas, read only by
                   the HARNESS model (the cart plays cybernoid2.sndh): u32 frame count, then per frame a u16 mask of the
                   registers that changed and their new values in ascending
                   order. Frame 0 is a full 14-register write, so a loop resets
                   the chip to the song's opening state.

A source mismatch is a hard error; the extracted files are then re-rendered by
tools/larcociel5/larco_model.py and compared to every captured Go frame.
"""
from __future__ import annotations
import struct, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SRC = Path("/tmp/opencode/larcociel5")
OUT = REPO / "apps/zig/assets/screens/larcociel5"
GO_REF = Path("/tmp/opencode/larco_ref")
REF_OUT = REPO / "tools/larcociel5/go_ref"

from PIL import Image

def rd(n): return (SRC / "assets/original" / n).read_bytes()

def extract(name, want_alpha):
    """(w, h, index grid). Asserts each pixel's R is index*17 and its alpha class
    is one of want_alpha — the only assumptions the Go shader makes of these PNGs."""
    im = Image.open(SRC / "assets/original" / name).convert("RGBA")
    w, h = im.size
    px = im.load()
    idx = [[0]*w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a not in want_alpha: sys.exit(f"{name}: ({x},{y}) alpha {a} unexpected")
            i = (r*15 + 127)//255
            if abs(i*17 - r) > 1: sys.exit(f"{name}: ({x},{y}) R {r} is not index*17 ({i})")
            idx[y][x] = i
    return w, h, idx, px

def main():
    OUT.mkdir(parents=True, exist_ok=True)

    w, h, bg, _ = extract("background.png", {255})
    assert (w, h) == (320, 200)
    (OUT / "bg.idx").write_bytes(bytes(bg[y][x] for y in range(200) for x in range(320)))

    w, h, rb, rbpx = extract("ribbon.png", {0, 255})
    assert (w, h) == (112, 50)
    rib = bytearray(112*50)
    for y in range(50):
        for x in range(112):
            if rbpx[x, y][3] > 0:
                if rb[y][x] == 0: sys.exit(f"ribbon: opaque index-0 pixel at ({x},{y}) is ambiguous")
                rib[y*112+x] = rb[y][x]
    (OUT / "ribbon.bin").write_bytes(bytes(rib))

    bat = bytearray(15*2048//8)
    for k in range(15):
        w, h, bi, bpx = extract(f"bat-{k}.png", {0, 255})
        assert (w, h) == (64, 32)
        for y in range(32):
            for x in range(64):
                if bpx[x, y][3] > 0:
                    if bi[y][x] != 4: sys.exit(f"bat-{k}: covered index {bi[y][x]} != 4")
                    o = y*64 + x
                    bat[(k*2048 + o) >> 3] |= 1 << (7 - (o & 7))
    (OUT / "bats.bin").write_bytes(bytes(bat))

    for n in ["palette.bin", "raster.bin", "font-colors.bin", "message.txt",
              "initial-motion.bin", "initial-history.bin"]:
        (OUT / n).write_bytes(rd(n))

    ym = rd("music.ym")
    frames = struct.unpack(">I", ym[12:16])[0]
    attr = struct.unpack(">I", ym[16:20])[0]
    if attr != 1: sys.exit(f"music.ym: unexpected attributes {attr}")
    data = 114  # after the three NUL-terminated text fields
    assert data + 16*frames <= len(ym), "music.ym: truncated"
    seq = bytearray(struct.pack("<I", frames))
    prev = [0]*14
    for f in range(frames):
        mask = 0; vals = []
        for r in range(14):
            v = ym[data + r*frames + f]
            if f == 0 or v != prev[r]:
                mask |= 1 << r; vals.append(v)
            prev[r] = v
        seq += struct.pack("<H", mask); seq += bytes(vals)
    (OUT / "music.seq").write_bytes(bytes(seq))
    print(f"music.seq: {frames} frames -> {len(seq)} bytes ({(len(seq)-4)/frames:.2f} B/frame)")

    sizes = {"bg.idx": 320*200, "ribbon.bin": 112*50, "bats.bin": 15*64*32//8,
             "palette.bin": 32, "raster.bin": 66, "font-colors.bin": 15300,
             "message.txt": len(rd("message.txt")), "initial-motion.bin": 12,
             "initial-history.bin": 100}
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
    N = 1200
    worst = 0
    for n in range(N):
        # frame n is the state AFTER n clock steps (Go: Update runs, then Draw),
        # so step first -- exactly as the Go tree's own checkpoint test does.
        if n > 0:
            lm.step_clock(clock)
            got = lm.render(n, clock, n-1)
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
