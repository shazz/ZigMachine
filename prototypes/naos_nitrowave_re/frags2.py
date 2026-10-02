"""Linearise a part's VBL program: template [T0, T1) + fragment stream [F0, F1)
of (cycles.w, nwords.w, code) records, as $1E82 (F2) / $1618 (menu) pack them.
    frags2.py DUMP T0 T1 F0 F1 OUT.bin"""
import struct
import sys

d = open(sys.argv[1], 'rb').read()
t0, t1, f0, f1 = (int(a, 16) for a in sys.argv[2:6])
out = bytearray(d[t0:t1])
p = f0
n = cyc = 0
while p < f1:
    c, w = struct.unpack('>HH', d[p:p + 4])
    out += d[p + 4:p + 4 + 2 * w]
    p += 4 + 2 * w
    n += 1
    cyc += c
open(sys.argv[6], 'wb').write(out)
print('template', t1 - t0, 'bytes; fragments', n, 'cycles', cyc, 'end', hex(p))
