# Contact sheet of the Hatari capture's 1 fps frames, labelled with SONG time (song 0 = video
# 28.0 s, the MOD's first audio). Frames: ffmpeg -i video/ays_rgb50.mp4 -vf fps=1,scale=320:240
# video/frames1s/f%03d.png (frame N = video second N-1).
# usage: sheet.py <frames dir> start_song_s end_song_s out.png [step]
import sys
from PIL import Image, ImageDraw

OFF = 28
src, a, b, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
step = int(sys.argv[5]) if len(sys.argv) > 5 else 1
ts = list(range(a, b, step))
cols = 6
rows = (len(ts) + cols - 1) // cols
W, H = 320, 240
sheet = Image.new('RGB', (cols * W, rows * (H + 14)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, t in enumerate(ts):
    try:
        im = Image.open('%s/f%03d.png' % (src, t + OFF + 1))
    except FileNotFoundError:
        continue
    x, y = (i % cols) * W, (i // cols) * (H + 14)
    sheet.paste(im, (x, y + 14))
    d.text((x + 2, y + 1), 's%d' % t, fill=(255, 255, 0))
sheet.save(out)
