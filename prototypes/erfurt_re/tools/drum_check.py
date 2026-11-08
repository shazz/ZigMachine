# Verify the drum model against a RAM dump: screen line y shows texture line
# P[rot + F[k]/4] in plane 0 and P[rot + B[k]/4] in plane 1 (B < 0: blank).
import struct, sys
r = open(sys.argv[1], 'rb').read()
W = lambda a: struct.unpack('>H', r[a:a + 2])[0]
S = lambda a: struct.unpack('>h', r[a:a + 2])[0]
L = lambda a: struct.unpack('>I', r[a:a + 4])[0]

pos = L(0x5B2E4)
circ = L(0x60C94)
print('pos', hex(pos), 'circ', circ, 'slot h $40ece', W(0x40ECE), '$40ed0', W(0x40ED0),
      'items $313be', W(0x313BE), 'cd0a', W(0x4CD0A), 'cd08', W(0x4CD08))
top, n = W(0x40ED2), W(0x40ED4)
fp, bp = L(0x4CD0C), L(0x4CD10)
print('top', top, 'n', n, 'F at', hex(fp), 'B at', hex(bp), 'ebb8', W(0x4EBB8), 'ebbe', W(0x4EBBE),
      'eba8', W(0x4EBA8), 'ebaa', W(0x4EBAA), 'ebcc', W(0x4EBCC), 'ebc2', W(0x4EBC2))
F = [S(fp + 2 * i) for i in range(n)]
B = [S(bp + 2 * i) for i in range(n)]
print('F', F)
print('B', B)
# configs at $41086, 16 bytes
for i in range(12):
    a = 0x41086 + 16 * i
    print('cfg', i, W(a), W(a + 2), hex(L(a + 4)), hex(L(a + 8)), hex(L(a + 12)))
scr = L(0x313C6) if len(sys.argv) < 3 else int(sys.argv[2], 0)
rotidx = W(0x4EBC2)
a4 = 0x5FB74 + 4 * rotidx
bad = 0
for k in range(n):
    y = W(0x4EBB8) + k
    line = scr + 0x10 + y * 160 + S(0x4EBBE)
    for plane, tab in ((0, F), (1, B)):
        if tab[k] < 0:
            want = [0] * 12
        else:
            p = L(a4 + tab[k])
            want = [W(p + 2 * j) for j in range(12)]
        got = [W(line + 0x20 + plane * 2 + 8 * j) for j in range(12)]
        if want != got:
            bad += 1
print('rot index', rotidx, 'mismatching plane-lines', bad, 'of', 2 * n)
