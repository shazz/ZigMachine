"""Dump the menu scroller's path table ($1b956, reset every 0x2ca frames).

Each frame reads TWO words: one in the VBL header (erase offset, $e10) and one
in the sprite program (draw offset, +$10). Offsets are bytes into a 230-byte
-a-line overscan screen, so row = off // 230, byte-in-row = off % 230.
"""
import struct

d = open('menu_td.bin', 'rb').read()
P = 0x1b956
n = 0x2ca * 2 + 8
w = struct.unpack(f'>{n}H', d[P:P + 2 * n])
for k in range(0, 40):
    e, dr = w[2 * k], w[2 * k + 1]
    print(f'{k:4d} erase {e:6d} (row {e // 230:3d} +{e % 230:3d})  draw {dr:6d} (row {dr // 230:3d} +{dr % 230:3d})')
print('...')
print('bytes after table end:', d[P + 0x2ca * 4:P + 0x2ca * 4 + 16].hex())
rows = [x // 230 for x in w[:0x2ca * 2]]
cols = [x % 230 for x in w[:0x2ca * 2]]
print('row range', min(rows), max(rows), 'col set', sorted(set(cols))[:20])
