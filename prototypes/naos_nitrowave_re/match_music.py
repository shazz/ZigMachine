"""Search the SNDH archive for chunks of each binary's music area (replay + data).

Usage: python3 match_music.py [key ...]
For each binary, slide 32-byte probes over [sig-0x1000, sig+0x6000) and report
every archive file containing a probe, ranked by probe hits.
"""
import glob
import sys
from collections import Counter

from load import files

ARCH = '/home/matt/projects/ZigMachine/prototypes/sndh_lf'
SIG = b'~a6J@g$"z'
arch = {p: open(p, 'rb').read() for p in glob.glob(f'{ARCH}/**/*.sndh', recursive=True)}
fs = files()
for k in (sys.argv[1:] or fs.keys()):
    d = fs[k]
    s = d.find(SIG)
    if s < 0:
        s = 0
    lo, hi = max(0, s - 0x1000), min(len(d), s + 0x6000)
    hits = Counter()
    probes = 0
    for o in range(lo, hi - 32, 32):
        pr = d[o:o + 32]
        if len(set(pr)) < 6:
            continue
        probes += 1
        for p, a in arch.items():
            if pr in a:
                hits[p] += 1
    print(k, 'probes', probes)
    for p, n in hits.most_common(8):
        print(f'   {n:4d} {p[len(ARCH) + 1:]}')
