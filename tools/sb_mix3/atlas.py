"""mix3's nine textures as ONE 256-wide, 8-bit atlas under ONE 256-colour palette.

Why one atlas: CHISEL AFFINE reads one texture an op, (U_MASK+1) texels a row, any
V inside the window. With every texture 256 texels wide and stacked, a single op can
draw triangles of every mesh, so the frame's triangles are depth-sorted together and
cut into a few long span lists instead of one list per texture (no Z on KESTREL: the
sort is what keeps the girls, the jar and the chrome in front of each other).
Smaller textures are tiled across the 256 (u wraps at 256 = a multiple of their width,
so the wrap is theirs too). Index 0 is the colour key (CON KEY_EN): mixer1_mark's
alpha < 128 and env1_3's dark texels (the addENV glass was a lerp: only its
highlights show). Halving: 512 -> 256, 256 env maps -> 128, the 128 button -> 64;
the 256 backdrop stays 256 (it spans the whole screen).
"""
from PIL import Image

# (texture, size in the atlas, keyed by alpha, keyed by darkness)
SLOTS = [
    ('BrunetteNaked_D', 256, False, False),
    ('BlondeNaked_D', 256, False, False),
    ('baked_beauty', 256, False, False),
    ('mixer1_mark', 256, True, False),
    ('back', 256, False, False),
    ('env1_1', 128, False, False),
    ('env1_2', 128, False, False),
    ('env1_3', 128, False, True),
    ('baked_knapp', 64, False, False),
]
WIDTH = 256
DARK_KEY = 40  # luminance (0..255) below which the glass's env texel is see-through


def _image(w, h, rows):
    im = Image.new('RGBA', (w, h))
    im.putdata([px for r in rows for px in r])
    return im


def build(textures):
    """textures: name -> (w, h, rows). Returns (atlas bytes, palette [(r,g,b)]*256, slot rows)."""
    rgb = Image.new('RGB', (WIDTH, sum(s for _, s, _, _ in SLOTS)))
    keyed = Image.new('L', rgb.size, 0)
    base = {}
    y = 0
    for name, size, by_alpha, by_dark in SLOTS:
        w, h, rows = textures[name]
        im = _image(w, h, rows).resize((size, size), Image.Resampling.BOX)
        lum = im.convert('L')
        for tx in range(0, WIDTH, size):
            rgb.paste(im.convert('RGB'), (tx, y))
            if by_alpha:
                keyed.paste(im.getchannel('A').point(lambda a: 255 if a < 128 else 0), (tx, y))
            if by_dark:
                keyed.paste(lum.point(lambda v: 255 if v < DARK_KEY else 0), (tx, y))
        base[name] = (y, size)
        y += size
    pal_img = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    flat = pal_img.getpalette()[:255 * 3]
    palette = [(0, 0, 0)] + [tuple(flat[3 * i:3 * i + 3]) for i in range(255)]
    idx = bytearray(b + 1 for b in pal_img.tobytes())
    for i, k in enumerate(keyed.tobytes()):
        if k:
            idx[i] = 0
    return bytes(idx), palette, base
