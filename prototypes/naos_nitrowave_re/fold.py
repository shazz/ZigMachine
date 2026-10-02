"""fold.py PROG.dis: print a linearised program with runs of identical-shape
blocks folded. Two instructions have the same shape when they differ only in
displacements / immediates; a block is a maximal run of shapes repeated with a
period of 1..64 instructions."""
import re
import sys

lines = [l.rstrip() for l in open(sys.argv[1])]
ins = [l.split(None, 2)[2] if len(l.split(None, 2)) > 2 else l for l in lines]
shape = [re.sub(r'#?\$-?[0-9a-f]+', 'N', i) for i in ins]
i, n = 0, len(shape)
while i < n:
    best = (1, 1)
    for p in range(1, 65):
        if i + 2 * p > n:
            break
        k = 1
        while i + (k + 1) * p <= n and shape[i + k * p:i + (k + 1) * p] == shape[i:i + p]:
            k += 1
        if k > 1 and k * p > best[0] * best[1]:
            best = (k, p)
    k, p = best
    if k > 1:
        print(f'---- {k} x [{p}] from {lines[i].split(":")[0]}')
        for j in range(i, i + p):
            print('     ', ins[j], '   |', ins[j + p] if j + p < n else '')
        i += k * p
    else:
        print('     ', lines[i])
        i += 1
