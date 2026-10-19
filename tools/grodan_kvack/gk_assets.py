#!/usr/bin/env python3
"""grodan_kvack asset converter.

Source of truth: the Go/Ebitengine production
  github.com/olivierh59500/grodan-kvack-kvack-demo  (assets/*.png)
whose 640x400 screen is exactly TWICE the Atari ST's 320x200: every layer's
screen rect halves, so this cart draws each layer at half the Go scale.

What the Go's Draw() actually composes (in Go px, 640x400):
  bgGreen (640x398) tiled, bgPink (640x398) tiled, 12 sprites (16x10, Scale(2,2)),
  then four scroll texts through three off-screen canvases, each coloured
  source-atop by a RASTER IMAGE:
    big   : 640x200 canvas, 24x33 glyphs at Scale(8,6), raster 160x96 Scale(4,2)
    up    : 32x400  canvas, 33x29 glyphs at Scale(1,1), raster 16x200 Scale(2,2)
    small : 320x32  canvas, 8x8   glyphs at Scale(1,1), rasters 160x4 Scale(2,2)
  Both raster sources are PURE VERTICAL GRADIENTS (one colour per row), i.e. a
  per-scanline colour register -- a REAL ST raster, played from the cart's
  `zg.copper` (CLAUDE.md: a fake raster must become a real one).

Our 320x200 mapping (halving the Go screen):
  bgGreen/bgPink -> 320x199 1-bit masks (the art is a clean 2x upscale)
  sprite         -> 204x10  1-bit mask, drawn 1:1 (Go drew it Scale(2,2))
  bsfont         -> 240x200 1-bit mask, drawn at Scale(4,3)
  upfonts        -> 330x227 1-bit mask, drawn at Scale(0.5,0.5) (sample 2x)
  lfont          ->  80x56  1-bit mask, drawn at Scale(1,1) in a 320x32 canvas
  bigraster.pal  ->  96 rows of one RGB colour  (our big canvas rows 0..95)
  upraster.pal   -> 200 rows of one RGB colour  (our up canvas rows 0..199)

Palette (8 entries): 0 black, 1 green(64,96,32), 2 pink(160,96,160),
3 sprite cyan(0,224,224), 4 BIG, 5 VERT, 6 SMALL (copper-rastered), 7 white
(the big canvas rows 96..99 fall past the 96-row raster and stay glyph-white,
 exactly as the Go's unpainted rows do).

Usage:  python3 tools/grodan_kvack/gk_assets.py [src_dir] [out_dir]
"""
import os, sys

try:
    from PIL import Image
except ImportError:
    sys.exit("need Pillow: pip install pillow")

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/opencode/grodan-kvack-kvack-demo/assets"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(__file__), "..", "..", "apps", "zig", "assets", "screens", "grodan_kvack")

BG_W, BG_H = 320, 199
SPRITE_W, SPRITE_H = 204, 10


def rgba(name):
    return Image.open(os.path.join(SRC, name)).convert("RGBA")


def pack_bits(mask, w, h, path, what):
    """mask: list of rows of 0/1 -> 1 bit/pixel, MSB-first, row-major."""
    nbytes = (w * h + 7) // 8
    out = bytearray(nbytes)
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if row[x]:
                o = y * w + x
                out[o >> 3] |= 0x80 >> (o & 7)
    with open(path, "wb") as f:
        f.write(out)
    print(f"  {what:10s} {w}x{h} -> {os.path.basename(path)} ({nbytes} B)")


def alpha_mask(img, x0=0, y0=0, w=None, h=None, key=(0, 0, 0)):
    """1 where alpha>127 (and, when key given, the colour is not the key)."""
    px = img.load()
    W = img.width if w is None else w
    H = img.height if h is None else h
    return [[1 if px[x0 + x, y0 + y][3] > 127 else 0 for x in range(W)] for y in range(H)]


def downscale_mask(img, key_alpha=True):
    """Take every other pixel/row (the Go halved screen is this art / 2)."""
    px = img.load()
    w, h = img.width // 2, img.height // 2
    return [[1 if px[2 * x, 2 * y][3] > 127 else 0 for x in range(w)] for y in range(h)]


def row_colors(img, crop=None):
    """One RGB per row, asserting the row really is uniform across x."""
    rgb = img.convert("RGB")
    px = rgb.load()
    x0, y0, w, h = crop if crop else (0, 0, rgb.width, rgb.height)
    cols = []
    for y in range(h):
        c = px[x0, y0 + y]
        for x in range(w):
            assert px[x0 + x, y0 + y] == c, f"row {y} not uniform at x={x}: {px[x0+x,y0+y]} != {c}"
        cols.append(c)
    return cols


def write_pal(cols, path, what):
    out = bytearray()
    for (r, g, b) in cols:
        out += bytes((r, g, b, 255))
    with open(path, "wb") as f:
        f.write(out)
    print(f"  {what:10s} {len(cols)} rows -> {os.path.basename(path)} ({len(out)} B)")


MAIN_GO = "main.go"


# ---- the Go's font maps (initBigScrollFont/initUpScrollFont/initSmallFont) --
# cell index -> col + row*10; a None means "in the map but not drawable" (a
# blank that still advances). Copied from main.go so the cell SEQUENCES below
# are the exact glyph stream each scroll text draws, with 0xFF = advance only.
def _cellmap(spec, blanks):
    m = {}
    for c, (col, row) in spec:
        m[c] = col + row * 10
    for c in blanks:
        m[c] = None
    return m


BIGCELL = _cellmap([
    ('!', (1, 0)), ("'", (5, 0)), ('"', (6, 0)), ('(', (7, 0)), (')', (8, 0)),
    ('.', (4, 1)), (',', (5, 1)), ('0', (6, 1)), ('1', (7, 1)), ('2', (8, 1)), ('3', (9, 1)),
    ('4', (0, 2)), ('5', (1, 2)), ('6', (2, 2)), ('7', (3, 2)), ('8', (4, 2)), ('9', (5, 2)), (':', (6, 2)),
    ('?', (1, 3)), ('A', (3, 3)), ('B', (4, 3)), ('C', (5, 3)), ('D', (6, 3)), ('E', (7, 3)), ('F', (8, 3)), ('G', (9, 3)),
    ('H', (0, 4)), ('I', (1, 4)), ('J', (2, 4)), ('K', (3, 4)), ('L', (4, 4)), ('M', (5, 4)), ('N', (6, 4)), ('O', (7, 4)), ('P', (8, 4)), ('Q', (9, 4)),
    ('R', (0, 5)), ('S', (1, 5)), ('T', (2, 5)), ('U', (3, 5)), ('V', (4, 5)), ('W', (5, 5)), ('X', (6, 5)), ('Y', (7, 5)), ('Z', (8, 5)),
], " -")
UPCELL = _cellmap([
    ('!', (1, 0)), ('(', (8, 0)), (')', (9, 0)), ('.', (4, 1)), ('#', (5, 2)), (':', (6, 2)),
    ('?', (1, 3)), ('A', (3, 3)), ('B', (4, 3)), ('C', (5, 3)), ('D', (6, 3)), ('E', (7, 3)), ('F', (8, 3)), ('G', (9, 3)),
    ('H', (0, 4)), ('I', (1, 4)), ('J', (2, 4)), ('K', (3, 4)), ('L', (4, 4)), ('M', (5, 4)), ('N', (6, 4)), ('O', (7, 4)), ('P', (8, 4)), ('Q', (9, 4)),
    ('R', (0, 5)), ('S', (1, 5)), ('T', (2, 5)), ('U', (3, 5)), ('V', (4, 5)), ('W', (5, 5)), ('X', (6, 5)), ('Y', (7, 5)), ('Z', (8, 5)),
], "0123456789 -,'")
SMALLCELL = _cellmap([
    ('!', (1, 0)), ("'", (7, 0)), ('(', (8, 0)), (')', (9, 0)),
    ('.', (4, 1)), ('/', (5, 1)), ('0', (6, 1)), ('1', (7, 1)), ('2', (8, 1)), ('3', (9, 1)),
    ('4', (0, 2)), ('5', (1, 2)), ('6', (2, 2)), ('7', (3, 2)), ('8', (4, 2)), ('9', (5, 2)), (':', (6, 2)),
    ('?', (1, 3)), ('A', (3, 3)), ('B', (4, 3)), ('C', (5, 3)), ('D', (6, 3)), ('E', (7, 3)), ('F', (8, 3)), ('G', (9, 3)),
    ('H', (0, 4)), ('I', (1, 4)), ('J', (2, 4)), ('K', (3, 4)), ('L', (4, 4)), ('M', (5, 4)), ('N', (6, 4)), ('O', (7, 4)), ('P', (8, 4)), ('Q', (9, 4)),
    ('R', (0, 5)), ('S', (1, 5)), ('T', (2, 5)), ('U', (3, 5)), ('V', (4, 5)), ('W', (5, 5)), ('X', (6, 5)), ('Y', (7, 5)), ('Z', (8, 5)),
], ' -,"')


def seq(text, cm, vertical):
    """The Go's NewScrollText, one entry per glyph: 0xFF = advance only."""
    out = []
    for ch in text:
        ch = ch.upper()
        if ch not in cm:
            if vertical:
                out.append(0xFF)     # vertical always advances
            continue                 # horizontal drops unmapped chars
        c = cm[ch]
        out.append(0xFF if c is None else c)
    return out


def write_cells(text_path, cm, vertical, path, what):
    text = open(text_path, "rb").read().decode("ascii").upper()
    cells = seq(text, cm, vertical)
    with open(path, "wb") as f:
        f.write(bytes(cells))
    print(f"  {what:10s} {len(cells)} cells -> {os.path.basename(path)}")


def write_text(src_var, path, what):
    import re
    text = open(os.path.join(SRC, "..", MAIN_GO)).read()
    m = re.search(r'\b' + src_var + r'\s*:=\s*"((?:[^"\\]|\\.)*)"', text)
    assert m, f"{src_var} not found in {MAIN_GO}"
    s = m.group(1).encode().decode("unicode_escape").upper()
    with open(path, "wb") as f:
        f.write(s.encode("ascii", "replace"))
    print(f"  {what:10s} {len(s)} chars -> {os.path.basename(path)}")


def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"src = {SRC}")
    print(f"out = {os.path.normpath(OUT)}")

    # ---- backgrounds (halve the Go's 2x art) -------------------------------
    bg = downscale_mask(rgba("Grodan_green.png"))
    assert len(bg) == BG_H and len(bg[0]) == BG_W, (len(bg[0]), len(bg))
    pack_bits(bg, BG_W, BG_H, os.path.join(OUT, "bg_green.raw"), "bgGreen")

    bp = downscale_mask(rgba("Grodan_pink.png"))
    # the pink art is not a clean 2x upscale; the half-res pattern keeps the
    # same hue/outline. Verified against the source by gk_verify.py.
    pack_bits(bp, BG_W, BG_H, os.path.join(OUT, "bg_pink.raw"), "bgPink")

    # ---- sprite strip (native, Go drew it Scale(2,2)) ----------------------
    sp = alpha_mask(rgba("sprite.png"))
    pack_bits(sp, SPRITE_W, SPRITE_H, os.path.join(OUT, "sprite.raw"), "sprite")

    # ---- fonts (1-bit masks; the Go draws them at its own scales) ----------
    bsf = alpha_mask(rgba("bsfont.png"))
    pack_bits(bsf, 240, 200, os.path.join(OUT, "bsfont.raw"), "bsfont")

    upf = alpha_mask(rgba("upfonts.png"))
    pack_bits(upf, 330, 227, os.path.join(OUT, "upfont.raw"), "upfont")

    lf = alpha_mask(rgba("lfont.png"))
    pack_bits(lf, 80, 56, os.path.join(OUT, "lfont.raw"), "lfont")

    # ---- raster colour tables (one colour per row) -------------------------
    up = rgba("upscrollraster.png")
    upcols = row_colors(up, (0, 0, 16, 200))          # the crop the Go masks with
    write_pal(upcols, os.path.join(OUT, "upraster.pal"), "upraster")

    bs = rgba("bigscrollraster.png")
    bscols = row_colors(bs, (0, 0, 160, 96))
    write_pal(bscols, os.path.join(OUT, "bigraster.pal"), "bigraster")

    # ---- the four messages (uppercased, exactly as the Go's font maps see them)
    write_text("mainText", os.path.join(OUT, "text_main.raw"), "mainText")
    write_text("vertText", os.path.join(OUT, "text_vert.raw"), "vertText")
    write_text("smallText1", os.path.join(OUT, "text_small1.raw"), "small1")
    write_text("smallText2", os.path.join(OUT, "text_small2.raw"), "small2")

    # ---- ...and the glyph-cell stream each one draws (the cart embeds these) --
    write_cells(os.path.join(OUT, "text_main.raw"), BIGCELL, False,
                os.path.join(OUT, "main.cells"), "main.cells")
    write_cells(os.path.join(OUT, "text_vert.raw"), UPCELL, True,
                os.path.join(OUT, "vert.cells"), "vert.cells")
    write_cells(os.path.join(OUT, "text_small1.raw"), SMALLCELL, False,
                os.path.join(OUT, "small1.cells"), "small1.cells")
    write_cells(os.path.join(OUT, "text_small2.raw"), SMALLCELL, False,
                os.path.join(OUT, "small2.cells"), "small2.cells")

    print("done")


if __name__ == "__main__":
    main()
