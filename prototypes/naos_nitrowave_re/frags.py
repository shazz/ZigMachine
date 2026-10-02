"""Linearise the menu's fragment stream ($1688..$c3f8 in MENU.PRG TEXT).

Each fragment is (cycles.w, nwords.w, nwords instruction words). The routine at
$1618 packs fragments into each overscan line's free cycles (nop-padding the
rest), so concatenating them gives the LOGICAL per-frame program.
Writes menu_frags.bin and prints fragment count + total cycles.
"""
import struct

d = open('menu_td.bin', 'rb').read()
p, end = 0x1688, 0xc3f8
out = bytearray()
n = cyc = 0
while p < end:
    c, w = struct.unpack('>HH', d[p:p + 4])
    out += d[p + 4:p + 4 + 2 * w]
    p += 4 + 2 * w
    n += 1
    cyc += c
open('menu_frags.bin', 'wb').write(out)
print('fragments', n, 'cycles', cyc, 'bytes', len(out), 'end', hex(p))
