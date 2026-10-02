"""sheet.py OUT.png COLS SCALE IMG...: contact sheet of frames, each labelled by its file name."""
import os
import sys

from PIL import Image, ImageDraw

out, cols, scale = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
ims = [Image.open(f).convert('RGB') for f in sys.argv[4:]]
w, h = int(ims[0].width * scale), int(ims[0].height * scale)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * (h + 12)), (40, 40, 40))
dr = ImageDraw.Draw(sheet)
for i, (im, f) in enumerate(zip(ims, sys.argv[4:])):
    x, y = (i % cols) * w, (i // cols) * (h + 12)
    sheet.paste(im.resize((w, h)), (x, y + 12))
    dr.text((x + 2, y), os.path.basename(f), fill=(255, 255, 0))
sheet.save(out)
