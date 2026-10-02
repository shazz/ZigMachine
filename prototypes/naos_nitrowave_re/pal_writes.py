"""pal_writes.py DUMP B C VARIANT: where (line, cycle) each colour-register
write of F3's generated VBL lands (gen_layout.py), the per-line colour 0/1
writes of the line template included."""
import struct
import sys

from gen_layout import F3, MD, Gen

mem = open(sys.argv[1], 'rb').read()
b, c, v = (int(x, 0) for x in sys.argv[2:5])
for addr, line, cyc, kind, payload in Gen(mem, F3, b, c, v).run():
    if kind == 'frag':
        _, w = struct.unpack('>HH', mem[payload:payload + 4])
        code = mem[payload + 4:payload + 4 + 2 * w]
        for ins in MD.disasm(code, addr):
            if '(a3)' in ins.op_str and ins.mnemonic.startswith('move'):
                print(f'line {line:3d} cyc {cyc:3d} {ins.mnemonic} {ins.op_str}')
    elif kind == 'tmpl' and '(a3)' in payload and line in (0, 1, 100, 228, 229, 255):
        print(f'line {line:3d} cyc {cyc:3d} TEMPLATE {payload}')
