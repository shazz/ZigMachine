"""sndh_match.py BLOB [W]: rank archive SNDHs by how many of their W-byte windows occur in BLOB.

Windows with < 10 distinct bytes are ignored (zero runs match everything).
A tune whose replay + data were relocated still matches on most windows (pointer-free data).
"""
import os
import sys

ROOT = '/home/matt/projects/ZigMachine/prototypes/sndh_lf'
blob = open(sys.argv[1], 'rb').read()
w = int(sys.argv[2]) if len(sys.argv) > 2 else 32
grams = {blob[i:i + w] for i in range(0, len(blob) - w) if len(set(blob[i:i + w])) >= 10}
res = []
for dp, _, fs in os.walk(ROOT):
    for f in fs:
        if not f.lower().endswith('.sndh'):
            continue
        p = os.path.join(dp, f)
        d = open(p, 'rb').read()
        if d[:4] == b'ICE!':
            continue
        wins = [d[i * w:(i + 1) * w] for i in range(len(d) // w)]
        wins = [x for x in wins if len(set(x)) >= 10]
        n = len(wins)
        if n == 0:
            continue
        hit = sum(x in grams for x in wins)
        if hit:
            res.append((hit, n, p[len(ROOT) + 1:]))
for hit, n, p in sorted(res, reverse=True)[:12]:
    print(f'{hit:5d}/{n:5d}  {p}')
