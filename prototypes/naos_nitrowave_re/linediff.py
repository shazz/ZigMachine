"""linediff.py A B BASE [LINES]: which 230-byte lines of the screen at BASE
(line 0 at BASE+160) differ between two dumps, as runs."""
import sys

a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
base = int(sys.argv[3], 16)
n = int(sys.argv[4]) if len(sys.argv) > 4 else 270
diff = []
for y in range(-1, n):
    lo = base + (0 if y < 0 else 160 + 230 * y)
    hi = lo + (160 if y < 0 else 230)
    d = sum(1 for i in range(lo, hi) if a[i] != b[i])
    if d:
        diff.append((y, d))
runs = []
for y, d in diff:
    if runs and runs[-1][1] == y - 1:
        runs[-1][1] = y
        runs[-1][2] += d
    else:
        runs.append([y, y, d])
print(' '.join(f'{r[0]}..{r[1]}({r[2]})' for r in runs))
