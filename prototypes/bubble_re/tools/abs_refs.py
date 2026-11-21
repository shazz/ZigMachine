#!/usr/bin/env python3
"""List the absolute (not relocated) addresses the code names, by range."""
import re
import sys

s = set(int(h, 16) for h in re.findall(r'[$]([0-9a-f]{4,6})\b', open(sys.argv[1]).read()))
v = sorted(x for x in s if 57862 <= x < 0xff0000)
print(len(v), hex(v[0]), hex(v[-1]))
print('below $1ee76:', [hex(x) for x in v if x < 0x1ee76][:20])
print('above $4d000:', [hex(x) for x in v if x > 0x4d000][:40])
