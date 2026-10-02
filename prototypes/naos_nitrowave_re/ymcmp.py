"""ymcmp.py A.ym B.ym: compare two 14-byte-a-frame YM register logs.

Reports (1) the best frame alignment of B against A and, at it, the fraction of
frames whose tone periods + volumes match exactly, and (2) a note-set histogram
similarity (order-free)."""
import sys
from collections import Counter


def load(p):
    d = open(p, 'rb').read()
    return [d[i:i + 14] for i in range(0, len(d) - 13, 14)]


def key(f):
    per = tuple((f[2 * c] | (f[2 * c + 1] & 15) << 8) if f[8 + c] & 31 else 0 for c in range(3))
    vol = tuple(f[8 + c] & 31 for c in range(3))
    return per + vol


a = [key(f) for f in load(sys.argv[1])]
b = [key(f) for f in load(sys.argv[2])]
best = (0, 0)
win = min(1500, len(a) - 1)
for lag in range(-400, 400):
    m = n = 0
    for i in range(win):
        j = i + lag
        if 0 <= j < len(b):
            n += 1
            m += a[i] == b[j]
    if n and m / n > best[0]:
        best = (m / n, lag)
print(f'aligned exact match: {best[0]:.3f} at lag {best[1]} frames')
ha = Counter(p for f in a for p in f[:3] if p)
hb = Counter(p for f in b for p in f[:3] if p)
inter = sum((ha & hb).values())
print(f'period histogram overlap: {inter / max(1, max(sum(ha.values()), sum(hb.values()))):.3f}')
