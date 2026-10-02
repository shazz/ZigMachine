"""avi2png.py IN.avi OUTDIR [STEP]: dump every STEP-th frame of a Hatari png-codec AVI.

Hatari's --avi-vcodec png stores each video frame as a whole PNG file, so the
frames are found by their signature; no video decoder needed.
"""
import os
import sys

d = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
step = int(sys.argv[3]) if len(sys.argv) > 3 else 50
os.makedirs(out, exist_ok=True)
SIG = b'\x89PNG\r\n\x1a\n'
END = b'IEND\xaeB`\x82'
p, n = 0, 0
while True:
    s = d.find(SIG, p)
    if s < 0:
        break
    e = d.find(END, s) + len(END)
    if n % step == 0:
        open(os.path.join(out, f'f{n:05d}.png'), 'wb').write(d[s:e])
    n += 1
    p = e
print(n, 'frames')
