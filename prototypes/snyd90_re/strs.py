"""strs.py FILE [MIN] [MAX]: printable runs (with offsets) that contain letters."""
import re
import sys

d = open(sys.argv[1], 'rb').read()
mn = int(sys.argv[2]) if len(sys.argv) > 2 else 12
mx = int(sys.argv[3]) if len(sys.argv) > 3 else 40
n = 0
for m in re.finditer(rb'[\x20-\x7e]{%d,}' % mn, d):
    s = m.group()
    if sum(c.isalpha() for c in s.decode()) < len(s) // 2:
        continue
    print(f'{m.start():06x}: {s[:200].decode()}')
    n += 1
    if n >= mx:
        break
