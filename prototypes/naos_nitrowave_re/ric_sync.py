"""ric_sync.py F N0 N1: which capture shows F1 model frame n (offset d from
the old sync) and which VBL's screen base it shows (lag L): every 3rd frame
of N0..N1 scored. After the base switch the sprites fix both: L = 0 (the
screen the VBL just drew), syncs 2813 / 2811 / 2734 / 2663 for F 0..3, 99.7%
of the pixels. Before it only colours change and they repeat: ambiguous."""
import sys
import numpy as np
from PIL import Image
sys.path.insert(0, '.')
import ric_pre
from ric_init import Init
from ric_model import Part
from ric_show import Regs, frame

F = int(sys.argv[1])
N0, N1 = int(sys.argv[2]), int(sys.argv[3])
sync = {0: 2817, 1: 2811, 2: 2738, 3: 2667}[F]
m = bytearray(0x80000)
f = open('disk/DEMO_RIC.BIN', 'rb').read()
m[0x800:0x800 + len(f)] = f
ric_pre.run(m)
Init(m).run(F)
p = Part.__new__(Part); p.m = m; p.shown = None
words = [int.from_bytes(m[0x68C2 + 2 * i:0x68C4 + 2 * i], 'big') for i in range(16)]
words[1] = 0
regs = Regs(words)
base = p.l(0x4791C)
snaps, bases, rstate = {}, [], {}
for n in range(N1):
    regs.vbl(p.m)
    p.vbl()
    bases.append(p.shown or base)
    if n >= max(0, N0 - 10):
        snaps[n] = bytes(p.m)
        rstate[n] = list(regs.p)
    # carry regs through a frame
    for k in range(1, 247):
        regs.hbl(p.m, k)
caps = {}
def cap(c):
    if c not in caps:
        caps[c] = np.array(Image.open(f'r{F}/f_{c:05d}.png').convert('RGB'))[::2, ::2]
    return caps[c]
res = {}
for L in range(0, 8):
    for d in range(-8, 4):
        s = []
        for n in range(N0, N1, 3):
            r = Regs(rstate[n])
            im = frame(snaps[n], bases[n - L], r, 0)
            c = cap(sync + n + d)
            s.append((c == im).all(-1).mean())
        res[(L, d)] = np.mean(s)
for k, v in sorted(res.items(), key=lambda kv: -kv[1])[:8]:
    print(k, round(v, 4))
