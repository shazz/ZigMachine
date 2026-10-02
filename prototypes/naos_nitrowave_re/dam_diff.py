"""dam_diff.py N: model vs oracle after N frames, differences grouped by screen
line (for the four screens) or by 256-byte block elsewhere."""
import subprocess
import sys

import dam_main as D
from dam_model import SNAP, Part

N = int(sys.argv[1])
subprocess.run(['./m68loop', SNAP, '4ac', str(N), 'dumps/od3', str(N)], check=True)
p = Part()
for _ in range(N):
    D.frame(p)
ref = open(f'dumps/od3.{N}', 'rb').read()
SCREENS = [0x3F400, 0x4DF00, 0x5CA00, 0x6B500]
out = {}
for i in range(0x2400, 0x7A000):
    if p.m[i] == ref[i]:
        continue
    key = None
    for s in SCREENS:
        if s <= i < s + 0xEB00:
            key = f'scr {s:X} line {(i - s - 160) // 230 if i >= s + 160 else -1}'
    key = key or f'block {i & ~0xFF:X}'
    out.setdefault(key, []).append(i)
for k, v in list(out.items())[:40]:
    print(k, len(v), 'first', hex(v[0]), 'model', p.m[v[0]:v[0] + 6].hex(), 'oracle', ref[v[0]:v[0] + 6].hex())
