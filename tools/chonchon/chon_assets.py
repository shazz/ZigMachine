#!/usr/bin/env python3
"""Rip CHONCHON (go-chonchon) assets to the cart's raw form, and verify.

Source: /tmp/opencode/chonchon (github.com/olivierh59500/go-chonchon).
Output: apps/zig/assets/screens/chonchon/* and a few Go frames under
tools/chonchon/go_ref/ for the headless harness.

Everything the cart draws that is NOT generated is an extraction of
assets/original/, and the extraction is PROVEN against the Go production's own
captured frames (see cmd/chonchon -capture):

  background.bin   320x200 ST 4-plane screen (160 bytes/row), verbatim
  font-source.bin  the Huffman-unpacked glyph bank the two ring scrollers read
  logo-path.bin    the 63-row chrome logo's per-row X (u16) and bank phase (u32)
  logo-y.bin       the logo's vertical transport
  scroll-y.bin     the scroller's two per-column wave tables
  message.bin      the scroller's message cursor table
  star-paths.bin / star-index.bin   the 100 authored star paths and their seeds
  palette.bin      the 16 ST colour words (big-endian) -- the static palette
  raster.bin       the 28 ST colour words the shader paints on rows 144..199
  volume-curve.bin the YM volume -> meter height curve
  meter-raw.bin    the meter bar mask (plane-0 words, 160 bytes/row)
  logo.idx         96 x 1071 logo-bank.png indices (R=idx*17, alpha 0 = 0)
  music.seq        the YM6 register stream as per-frame deltas, read only by
                   the HARNESS model (the cart plays rollout.sndh #2): u32
                   frame count, then per frame a u16 mask of the
                   registers that changed and their new values in ascending
                   order. Frame 0 is a full 14-register write, so a loop resets
                   the chip to the song's opening state.

A source mismatch is a hard error; the files are then re-rendered by
tools/chonchon/chon_model.py and compared to every captured Go frame.
"""
from __future__ import annotations
import struct, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SRC = Path("/tmp/opencode/chonchon")
OUT = REPO / "apps/zig/assets/screens/chonchon"
GO_REF = Path("/tmp/opencode/chon_ref")
REF_OUT = REPO / "tools/chonchon/go_ref"

from PIL import Image


def rd(n):
    return (SRC / "assets/original" / n).read_bytes()


def extract_index(name, want_alpha):
    """(w, h, index grid). Asserts each pixel's R is index*17 and its alpha class
    is one of want_alpha -- the only assumptions the Go shader makes of the PNG."""
    im = Image.open(SRC / "assets/original" / name).convert("RGBA")
    w, h = im.size
    px = im.load()
    idx = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a not in want_alpha:
                sys.exit(f"{name}: ({x},{y}) alpha {a} unexpected")
            i = (r * 15 + 127) // 255
            if abs(i * 17 - r) > 1:
                sys.exit(f"{name}: ({x},{y}) R {r} is not index*17 ({i})")
            idx[y][x] = i
    return w, h, idx


def extract_ym(archive: bytes) -> bytes:
    """The production's music.ym is an LHa (-lh5-) archive holding ROLLOUT2.YM,
    a YM6 chip dump by Jochen Hippel ('Rollout tune 2'). Decompress it, then
    turn the interleaved per-frame register table into the cart's delta stream."""
    with tempfile.TemporaryDirectory() as td:
        arc = Path(td) / "music.ym"
        arc.write_bytes(archive)
        try:
            subprocess.run(["7z", "x", "-y", f"-o{td}/x", str(arc)],
                           check=True, capture_output=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            sys.exit(f"cannot unpack the LHa music archive (needs 7z): {e}")
        inner = sorted((Path(td) / "x").glob("*.YM")) + sorted((Path(td) / "x").glob("*.ym"))
        if not inner:
            sys.exit("the LHa archive held no .YM file")
        ym = inner[0].read_bytes()
    if ym[:4] != b"YM6!" or ym[4:12] != b"LeOnArD!":
        sys.exit(f"unexpected YM header {ym[:12]!r}")
    frames = struct.unpack(">I", ym[12:16])[0]
    attrs = struct.unpack(">I", ym[16:20])[0]
    if attrs & 1 == 0:
        sys.exit(f"music: expected an interleaved YM6 table, attrs={attrs}")
    o = 34
    for _ in range(3):  # name, author, comment
        o = ym.index(0, o) + 1
    assert o + frames * 16 <= len(ym), "music: truncated register table"
    seq = bytearray(struct.pack("<I", frames))
    prev = [0] * 14
    for f in range(frames):
        mask = 0
        vals = []
        for r in range(14):
            v = ym[o + r * frames + f]
            if f == 0 or v != prev[r]:
                mask |= 1 << r
                vals.append(v)
            prev[r] = v
        seq += struct.pack("<H", mask)
        seq += bytes(vals)
    print(f"music.seq: {frames} frames -> {len(seq)} bytes ({(len(seq)-4)/frames:.2f} B/frame)")
    return bytes(seq)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    verbatim = ["background.bin", "font-source.bin", "logo-path.bin", "logo-y.bin",
                "scroll-y.bin", "message.bin", "star-paths.bin", "star-index.bin",
                "palette.bin", "raster.bin", "volume-curve.bin", "meter-raw.bin"]
    for n in verbatim:
        (OUT / n).write_bytes(rd(n))

    w, h, logo = extract_index("logo-bank.png", {0, 255})
    assert (w, h) == (96, 1071), (w, h)
    (OUT / "logo.idx").write_bytes(bytes(logo[y][x] for y in range(h) for x in range(w)))

    (OUT / "music.seq").write_bytes(extract_ym(rd("music.ym")))

    sizes = {"background.bin": 32000, "font-source.bin": 64807, "logo-path.bin": 40000,
             "logo-y.bin": 724, "scroll-y.bin": 5832, "message.bin": 190,
             "star-paths.bin": 54000, "star-index.bin": 600, "palette.bin": 32,
             "raster.bin": 56, "volume-curve.bin": 16, "meter-raw.bin": 8320,
             "logo.idx": 96 * 1071}
    for n, want in sizes.items():
        got = (OUT / n).stat().st_size
        assert got == want, f"{n}: {got} != {want}"
    print("ripped:", ", ".join(f"{n}={v}" for n, v in sizes.items()))

    if not GO_REF.is_dir():
        print(f"note: {GO_REF} absent; skipped the Go-frame comparison")
        return
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import chon_model
    m = chon_model.Model(OUT)
    c = m.new()
    N = 1200
    for n in range(N):
        if n > 0:
            m.step(c)
            m.apply_meter(c, m.ym.at(n - 1))
            got = m.render(c, with_logo=True)
        else:
            got = m.render0(c)
        want = chon_model.ref_rgb(GO_REF / f"{n:06d}.png")
        d = sum(1 for p, q in zip(got, want) if p != q)
        if d:
            sys.exit(f"the extracted assets differ from the Go frame {n} by {d} bytes")
    print(f"the extracted assets reproduce all {N} captured Go frames byte for byte")
    REF_OUT.mkdir(parents=True, exist_ok=True)
    keep = [0, 1, 2, 10, 50, 100, 149, 200, 320, 500, 800, 1000, 1100, 1199]
    for n in keep:
        (REF_OUT / f"{n:06d}.png").write_bytes((GO_REF / f"{n:06d}.png").read_bytes())
    print(f"kept {len(keep)} Go frames under {REF_OUT.relative_to(REPO)}")

    # The two ring banks after 100 steps, pinned by the Go tree's own test
    # (internal/source/testdata/scroll-bank-{0,1}-100.bin.gz).
    import gzip
    c = m.new()
    for _ in range(100):
        m.step(c)
    for i in range(2):
        want = gzip.decompress((SRC / f"internal/source/testdata/scroll-bank-{i}-100.bin.gz").read_bytes())
        assert bytes(c["Ring"][i]) == want, f"ring bank {i} differs from the Go tree's native memory"
    print("the two ring banks equal the Go tree's native 68000 scroll-bank checkpoints")


if __name__ == "__main__":
    main()
