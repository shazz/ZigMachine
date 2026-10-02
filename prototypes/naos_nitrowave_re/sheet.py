"""Contact sheet: sheet.py OUT.png COLS img... (each image halved)."""
import sys

from PIL import Image, ImageDraw

out, cols, paths = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
ims = [Image.open(p).convert('RGB') for p in paths]
ims = [im.resize((im.width // 2, im.height // 2), Image.NEAREST) for im in ims]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sh = Image.new('RGB', (cols * w, rows * (h + 12)), (40, 40, 40))
dr = ImageDraw.Draw(sh)
for k, (im, p) in enumerate(zip(ims, paths)):
    x, y = (k % cols) * w, (k // cols) * (h + 12)
    sh.paste(im, (x, y + 12))
    dr.text((x + 2, y), p.rsplit('/', 1)[-1], fill=(255, 255, 0))
sh.save(out)
