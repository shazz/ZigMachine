"""irregular.py PROG.dis: within each run fold.py folds, list the repetitions
whose operands (displacements / immediates) differ from the first one's."""
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
        first = ins[i:i + p]
        odd = [(r, j, ins[i + r * p + j]) for r in range(1, k) for j in range(p) if ins[i + r * p + j] != first[j]]
        if odd:
            print(f'{lines[i].split(":")[0]} {k}x[{p}]: {len(odd)} operands differ, e.g. {odd[:4]}')
        i += k * p
    else:
        i += 1
