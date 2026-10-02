"""cmp_dumps.py A B [lo hi]: count differing bytes of two 512 KB dumps in [lo, hi),
grouped in 4 KB pages (the stack page $7F000.. is left out by default)."""
import sys

a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
lo = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x100
hi = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x7F000
pages = {}
for i in range(lo, hi):
    if a[i] != b[i]:
        pages[i >> 12] = pages.get(i >> 12, 0) + 1
print(sum(pages.values()), 'bytes differ;', ' '.join(f'${p << 12:05X}:{n}' for p, n in sorted(pages.items())[:30]))
