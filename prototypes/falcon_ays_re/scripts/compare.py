# Side by side: the original (scripts/grab.py frames; the capture's 240 rows hold the 200-line
# screen scaled x1.2, so they are scaled back to 320x200) and the port (scripts/shots.mjs).
# usage: compare.py <orig dir> <port dir> <out.png> t1 t2 ...
import sys

from PIL import Image, ImageDraw

odir, pdir, out = sys.argv[1], sys.argv[2], sys.argv[3]
ts = [float(t) for t in sys.argv[4:]]
sheet = Image.new("RGB", (2 * 320 + 8, len(ts) * 214), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, t in enumerate(ts):
    y = i * 214
    o = Image.open("%s/orig_s%07.2f.png" % (odir, t)).resize((320, 200))
    p = Image.open("%s/port_s%07.2f.png" % (pdir, t))
    sheet.paste(o, (0, y + 14))
    sheet.paste(p, (328, y + 14))
    d.text((2, y + 1), "original s%.1f" % t, fill=(255, 255, 0))
    d.text((330, y + 1), "port s%.1f" % t, fill=(255, 255, 0))
sheet.save(out)
