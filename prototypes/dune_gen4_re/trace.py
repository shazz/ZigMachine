"""trace.py HATARI.out: the VBL of every traced breakpoint hit, named.

Breakpoints set with `b pc = <addr> :trace :file <vblonly.ini>` print their
condition and then `e VBL`; this pairs the two. Addresses are TEXT $21006 + the
offsets below (the launcher's load address).
"""
import re
import sys

TEXT = 0x21006
NAMES = {0x188: 'title fade', 0x1A4: 'title SingSong', 0x1018A: 'menu', 0x101CA: 'menu fade',
         0x10A06: 'F1', 0x10A88: 'F1 fade', 0x10A8E: 'F1 init', 0x44C4: 'main VBL', 0x59CC: 'F2', 0x5A1C: 'F2 VBL'}
cur = None
for line in open(sys.argv[1]):
    m = re.match(r'\s+pc = \$([0-9a-f]+)', line)
    if m:
        cur = int(m.group(1), 16) - TEXT
    v = re.search(r'#(\d+) \(dec\)', line)
    if v and cur is not None:
        print(f'{int(v.group(1)):6d}  {NAMES.get(cur, hex(cur))}')
        cur = None
