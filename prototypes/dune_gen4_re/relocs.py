"""relocs.py PRG: print the TEXT offsets of every relocated long (GEMDOS fixup table)."""
import struct
import sys

d = open(sys.argv[1], 'rb').read()
_, t, dl, b, s = struct.unpack('>HIIII', d[:18])
p = 28 + t + dl + s
first = struct.unpack('>I', d[p:p + 4])[0]
p += 4
out = []
if first:
    o = first
    out.append(o)
    while True:
        c = d[p]
        p += 1
        if c == 0:
            break
        o += 254 if c == 1 else c
        if c != 1:
            out.append(o)
for o in out:
    print(f'{o:06x} -> {struct.unpack(">I", d[28 + o:32 + o])[0]:06x}')
