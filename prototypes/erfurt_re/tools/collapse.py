# Collapse runs of identical instructions in a dis.py listing (unrolled nops/moves).
import sys
out, prev, n = [], None, 0
for line in open(sys.argv[1]):
    k = line[30:].strip()
    if k == prev:
        n += 1
        continue
    if n:
        out.append('        ... x%d more\n' % n)
    out.append(line)
    prev, n = k, 0
open(sys.argv[2], 'w').writelines(out)
