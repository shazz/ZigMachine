"""Compare the menu model with the Hatari capture, frame by frame.

    cmp_menu.py N_MODEL_FRAMES FIRST_CAPTURE [LAST_CAPTURE]
Capture pixel (x, y) is screen line y-1, pixel x+4 (fit_geom.py on frame 1700).
Finds the capture frame matching model frame 40 (sync), then reports the
per-frame pixel match over the whole run.
"""
import sys

import numpy as np
from PIL import Image

from menu_model import menu_frames
from stimg import chunky, palette

DIR = __import__('os').environ.get('CAPDIR', 'mshots')

N, C0 = int(sys.argv[1]), int(sys.argv[2])
C1 = int(sys.argv[3]) if len(sys.argv) > 3 else C0 + N + 200
pal = None


def model_rgb(mem, shown):
    idx = np.zeros((276, 416), np.uint8)
    idx[1:261, :412] = chunky(mem, shown + 160, 230, 260, 460)[:, 4:416]  # capture x 412.. is black
    return pal[idx]


def cap(n):
    try:
        return np.array(Image.open(f'{DIR}/m_{n:05d}.png').convert('RGB'))[::2, ::2]
    except FileNotFoundError:
        return None


frames = []
for shown, mem in menu_frames(N, int(__import__("os").environ.get("VARIANT", "0"))):
    if pal is None:
        pal = palette(mem, 0xC3F8)
    frames.append(model_rgb(mem, shown))
caps = {n: cap(n) for n in range(C0, C1)}
def score(off):
    ks = [k for k in range(0, len(frames), 7) if caps.get(k + off) is not None]
    return sum(float((caps[k + off] == frames[k]).all(-1).mean()) for k in ks) / max(len(ks), 1)


if 'OFF' in __import__('os').environ:
    off = int(__import__('os').environ['OFF'])
else:
    sync = max((score(o), o) for o in range(C0, C1 - N))
    off = sync[1]
    print('model frame 0 <-> capture %d (mean %.5f)' % (off, sync[0]))
marks = []
for k, f in enumerate(frames):
    c = caps.get(k + off)
    if c is None:
        continue
    eq = float((c[:258] == f[:258]).all(-1).mean())  # rows 258+: bottom-border lines, fitted separately
    marks.append('.' if eq == 1.0 else 'x')
print(''.join(marks))
print(f'{len(frames)} frames, {marks.count("x")} not pixel-exact')
if len(sys.argv) > 4:
    k = int(sys.argv[4])
    Image.fromarray(np.concatenate([frames[k], caps[k + off]], 1)).resize((1664, 552), 0).save('/dev/shm/nw_cmp.png')
