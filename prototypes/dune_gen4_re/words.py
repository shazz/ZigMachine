"""words.py OFF LEN [w|b]: dump depacked DUNE TEXT (dune_unpacked.prg) as words or bytes."""
import struct
import sys

d = open('dune_unpacked.prg', 'rb').read()[28:]
off, n = int(sys.argv[1], 0), int(sys.argv[2], 0)
mode = sys.argv[3] if len(sys.argv) > 3 else 'w'
step = 2 if mode == 'w' else 1
row = 16 if mode == 'w' else 32
for a in range(off, off + n, row):
    if mode == 'w':
        vals = [f'{struct.unpack(">H", d[i:i+2])[0]:04x}' for i in range(a, min(a + row, off + n), 2)]
    else:
        vals = [f'{d[i]:02x}' for i in range(a, min(a + row, off + n))]
    print(f'{a:05x}: ' + ' '.join(vals))
