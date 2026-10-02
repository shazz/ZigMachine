"""regs.py LOG VBL: the d0..d7,a0..a7 Hatari printed (`r`) at the dump taken
at VBL, as m68loop's REGS string."""
import re
import sys

log = open(sys.argv[1], errors='replace').read()
want = int(sys.argv[2])
blocks = log.split('> r')
for blk in blocks[1:]:
    regs = dict(re.findall(r'([AD][0-7]) ([0-9A-F]{8})', blk[:600]))
    # the save.ini that printed this block was the one for this VBL
    before = blocks[blocks.index(blk) - 1]
    m = re.findall(r'save(\d+)\.ini', before)
    if m and int(m[-1]) == want and len(regs) >= 16:
        print(','.join(regs[f'D{i}'] for i in range(8)) + ',' + ','.join(regs[f'A{i}'] for i in range(8)))
        break
