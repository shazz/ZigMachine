# Disassemble COMFORT_unpacked.PRG's TEXT (68030) with Capstone, linear sweep, resyncing on
# failure. Offsets printed are TEXT-relative (= DATA-relative addresses continue at TEXT size).
# Relocated longs are annotated with the segment they point into.
# usage: dis.py <COMFORT_unpacked.PRG> <out.dis>
import struct
import sys

import capstone

d = open(sys.argv[1], 'rb').read()
magic, tlen, dlen, blen, slen = struct.unpack('>HIIII', d[:18])
assert magic == 0x601A
text = d[28:28 + tlen]
img = d[28:28 + tlen + dlen]
# relocation table: first long offset, then byte deltas (1 = +254)
rel = set()
p = 28 + tlen + dlen + slen
first = struct.unpack('>I', d[p:p + 4])[0]
p += 4
if first:
    off = first
    rel.add(off)
    while True:
        b = d[p]
        p += 1
        if b == 0:
            break
        if b == 1:
            off += 254
            continue
        off += b
        rel.add(off)


def seg(a):
    if a < tlen:
        return 'T'
    if a < tlen + dlen:
        return 'D'
    return 'B'


md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_030 | capstone.CS_MODE_BIG_ENDIAN)
out = open(sys.argv[2], 'w')
pc = 0
while pc < tlen:
    ins = next(md.disasm(text[pc:pc + 16], pc), None)
    if ins is None:
        out.write('%06x: dc.w $%04x\n' % (pc, struct.unpack('>H', text[pc:pc + 2])[0]))
        pc += 2
        continue
    notes = []
    for r in range(pc, pc + ins.size - 3, 2):
        if r in rel:
            v = struct.unpack('>I', img[r:r + 4])[0]
            notes.append('%s:%06x' % (seg(v), v))
    out.write('%06x: %-8s %s%s\n' % (pc, ins.mnemonic, ins.op_str,
                                     ('    ; ' + ' '.join(notes)) if notes else ''))
    pc += ins.size
print('TEXT %d DATA %d BSS %d relocs %d' % (tlen, dlen, blen, len(rel)))
