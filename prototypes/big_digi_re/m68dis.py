"""dis.py FILE OFFSET LEN [BASE]: Capstone 68000 disassembly of a byte range."""
import sys

import capstone

d = open(sys.argv[1], 'rb').read()
off = int(sys.argv[2], 0)
n = int(sys.argv[3], 0)
base = int(sys.argv[4], 0) if len(sys.argv) > 4 else off
md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
md.skipdata = True
for ins in md.disasm(d[off:off + n], base):
    print(f'{ins.address:06x}: {ins.bytes.hex():20s} {ins.mnemonic:8s} {ins.op_str}')
