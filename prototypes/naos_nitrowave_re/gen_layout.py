"""Replay a part's VBL-code generator to know WHERE each instruction lands:
its address in the generated code, its overscan line, and its cycle in the
line (counted from the line's first template instruction). Aragorn's three
generators (menu $316, F2 $F8E, F3 $40BCA) share one shape:

  header template [H0, H1); [variant nops]
  256 lines: L0 template, slot A (d0 = A, or A_SPECIAL on line $E5) + its
  template, slot B (d0 = B) + template, slot C (d0 = C)
  slot fill ($1618 / $1E82 / $3C82C): take fragments (cycles, nwords, code)
  while cycles <= d0 and d0 - cycles != 2; then (d0 >> 2) nops, the last one
  replaced by exg d0,d0 (6 cycles) when d0 & 2.

layout(cfg) -> list of (code_addr, line, cycle, kind, payload) for every
fragment and template instruction (kind 'frag' / 'tmpl' / 'nop').
"""
import struct

import capstone

MD = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
# 68000 cycles (ST-rounded) of the template instructions these generators use
TCYC = {'move.b d0, (a0)': 8, 'move.b d1, (a0)': 8, 'move.b d0, (a1)': 8, 'move.b d1, (a1)': 8,
        'nop ': 4, 'move.w (a2)+, (a3)': 12, 'move.w (a2)+, $2(a3)': 16}

F3 = dict(base=0x7A000, header=(0x3B812, 0x3C7D8), line0=(0x3C7D8, 0x3C7DE),
          tmpl_a=(0x3C7DE, 0x3C7E8), tmpl_a_special=(0x3C7E8, 0x3C7F6), tmpl_b=(0x3C7F6, 0x3C7FA),
          a=0x16, a_special=6, frags=(0x3C89C, 0x409C0), lines=256, special=0xE5)


def template(mem, lo, hi):
    out = []
    for ins in MD.disasm(bytes(mem[lo:hi]), lo):
        text = f'{ins.mnemonic} {ins.op_str}'
        out.append((ins.size, TCYC.get(text, None), text))
    return out


class Gen:
    def __init__(self, mem, cfg, b, c, variant):
        self.mem, self.cfg, self.b, self.c, self.variant = mem, cfg, b, c, variant
        self.p = cfg['frags'][0]
        self.addr = cfg['base']
        self.out = []

    def emit(self, line, cyc, kind, size, payload):
        self.out.append((self.addr, line, cyc, kind, payload))
        self.addr += size

    def tmpl(self, rng, line, cyc):
        for size, c, text in template(self.mem, *rng):
            self.emit(line, cyc, 'tmpl', size, text)
            cyc += c or 0
        return cyc

    def fill(self, d0, line, cyc):
        m, end = self.mem, self.cfg['frags'][1]
        while self.p != end:
            c, w = struct.unpack('>HH', m[self.p:self.p + 4])
            if d0 - c < 0 or d0 - c == 2:
                break
            self.emit(line, cyc, 'frag', 2 * w, self.p)
            d0 -= c
            cyc += c
            self.p += 4 + 2 * w
        n, half = d0 >> 2, d0 & 2
        for k in range(n):
            last = half and k == n - 1
            self.emit(line, cyc, 'nop', 2, 'exg' if last else 'nop')
            cyc += 6 if last else 4
        return cyc

    def run(self):
        cfg = self.cfg
        self.tmpl(cfg['header'], -1, 0)
        for _ in range(self.variant):
            self.emit(-1, 0, 'nop', 2, 'nop')
        for line in range(cfg['lines']):
            cyc = self.tmpl(cfg['line0'], line, 0)
            special = line + 1 == cfg['special']
            cyc = self.fill(cfg['a_special'] if special else cfg['a'], line, cyc)
            cyc = self.tmpl(cfg['tmpl_a_special'] if special else cfg['tmpl_a'], line, cyc)
            cyc = self.fill(self.b, line, cyc)
            cyc = self.tmpl(cfg['tmpl_b'], line, cyc)
            self.fill(self.c, line, cyc)
        return self.out


if __name__ == '__main__':
    import sys
    mem = open(sys.argv[1], 'rb').read()
    b, c, v = (int(x, 0) for x in sys.argv[2:5])
    out = Gen(mem, F3, b, c, v).run()
    print('ends at', hex(out[-1][0]), 'items', len(out))
    for item in out[:5] + [o for o in out if o[3] == 'tmpl' and 'a3' in str(o[4])][:6]:
        print(hex(item[0]), item[1:4], item[4] if item[3] != 'frag' else hex(item[4]))
