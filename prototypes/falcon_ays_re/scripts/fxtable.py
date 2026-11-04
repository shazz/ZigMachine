# Dump the 8xx -> routine table: the timer-D music interrupt (TEXT $75a) reads the replay's sync
# byte ($128e), and for a value v != $FF copies longs 2,3,4 of the 32-byte entry at
# $13fd74 + 32*v into $140554 (timer-rate rout), $140558 (VBL rout) and $14055c (main-loop rout).
# Addresses are image offsets (TEXT starts at 0, DATA at TEXT size).
# usage: fxtable.py <COMFORT_unpacked.PRG>
import struct
import sys

d = open(sys.argv[1], 'rb').read()
tlen = struct.unpack('>I', d[2:6])[0]
img = d[28:]
base = 0x13FD74
for v in range(0, 64):
    e = struct.unpack('>8I', img[base + 32 * v: base + 32 * v + 32])
    print('8%02X %3d  ' % (v, v) + ' '.join('%06x' % x for x in e))
for a in (0x140554, 0x140558, 0x14055C):
    print('%06x = %06x' % (a, struct.unpack('>I', img[a:a + 4])[0]))
