"""dis_runs.py RAM.bin START LEN: disassemble [START, START+LEN) of a memory image, folding runs.

The parts' code is mostly unrolled: a routine is a few instructions and then the same
instruction shape hundreds of times with other displacements. Consecutive instructions
(or two-instruction pairs) whose shape matches (numbers replaced by N) print as one line:
'xCOUNT  first ... last'. Stops at the first rts after START+LEN.
"""
import re
import sys

import capstone

d = open(sys.argv[1], 'rb').read()
start = int(sys.argv[2], 0)
n = int(sys.argv[3], 0)
md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
md.skipdata = True
ins = [(i.address, f'{i.mnemonic} {i.op_str}') for i in md.disasm(d[start:start + n], start)]


def shape(s: str) -> str:
    return re.sub(r'-?\$[0-9a-f]+', 'N', s)


i = 0
while i < len(ins):
    for width in (1, 2, 3, 4, 5, 6):
        k = i
        while k + 2 * width <= len(ins) and all(
                shape(ins[k + j][1]) == shape(ins[k + width + j][1]) for j in range(width)):
            k += width
        reps = (k - i) // width + 1
        if reps >= 3:
            first = '; '.join(t for _, t in ins[i:i + width])
            last = '; '.join(t for _, t in ins[k:k + width])
            print(f'{ins[i][0]:06x}: x{reps:<4d} {first}  ...  {last}')
            i = k + width
            break
    else:
        print(f'{ins[i][0]:06x}:        {ins[i][1]}')
        i += 1
