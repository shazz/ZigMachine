"""cmp.py CART.ppm HATARI.png OUT.png: the cart's frame above Hatari's, same window
(ST x -40..359, y -29..239), doubled, with the differing pixels marked red in a
third panel."""
import sys

from PIL import Image

a = Image.open(sys.argv[1]).convert('RGB').crop((0, 11, 400, 280))
b = Image.open(sys.argv[2]).convert('RGB').resize((416, 276), Image.NEAREST).crop((8, 0, 408, 269))
d = Image.new('RGB', a.size)
pa, pb, pd = a.load(), b.load(), d.load()
for y in range(a.size[1]):
    for x in range(a.size[0]):
        ca = tuple(round(c * 7 / 255) for c in pa[x, y])
        cb = tuple(c // 34 for c in pb[x, y])
        pd[x, y] = (255, 0, 0) if ca != cb else tuple(c // 3 for c in pb[x, y])
out = Image.new('RGB', (400, 3 * 269 + 8))
for i, im in enumerate((a, b, d)):
    out.paste(im, (0, i * 273))
out.resize((800, out.size[1] * 2), Image.NEAREST).save(sys.argv[3])
