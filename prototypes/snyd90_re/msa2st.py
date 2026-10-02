"""MSA -> raw .ST sector image."""
import struct
import sys

d = open(sys.argv[1], 'rb').read()
magic, spt, sides, start, end = struct.unpack('>HHHHH', d[:10])
assert magic == 0x0e0f
out = bytearray()
p = 10
for t in range(start, end + 1):
    for s in range(sides + 1):
        n = struct.unpack('>H', d[p:p + 2])[0]
        p += 2
        blk = d[p:p + n]
        p += n
        if n == spt * 512:
            out += blk
            continue
        i = 0
        o = bytearray()
        while i < len(blk):
            b = blk[i]
            i += 1
            if b == 0xE5:
                v = blk[i]
                c = struct.unpack('>H', blk[i + 1:i + 3])[0]
                i += 3
                o += bytes([v]) * c
            else:
                o.append(b)
        assert len(o) == spt * 512, (t, s, len(o))
        out += o
open(sys.argv[2], 'wb').write(out)
print(spt, sides + 1, start, end, len(out))
