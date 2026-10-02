"""Pull PNG frames out of a Hatari --avi-vcodec png recording (no ffmpeg here).

    avi_frames.py IN.avi OUTPREFIX STEP [FIRST] [LAST]
Writes OUTPREFIX_<frame>.png for every STEP-th frame. Frame n = VBL n of the run.
"""
import sys

d = open(sys.argv[1], 'rb').read()
pre, step = sys.argv[2], int(sys.argv[3])
first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
last = int(sys.argv[5]) if len(sys.argv) > 5 else 1 << 30
SIG, END = b'\x89PNG\r\n\x1a\n', b'IEND\xaeB`\x82'
n, i = 0, d.find(SIG)
while i >= 0:
    e = d.find(END, i) + len(END)
    if first <= n <= last and (n - first) % step == 0:
        open(f'{pre}_{n:05d}.png', 'wb').write(d[i:e])
    n += 1
    i = d.find(SIG, e)
print('frames', n)
