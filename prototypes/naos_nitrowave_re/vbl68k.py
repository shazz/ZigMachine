"""A tiny interpreter for the menu's VBL program (template $e10..$15d2 + the
linearised fragment stream), restricted to the instructions that move data.

The border-opening / sync code (a0, a1, d0, d1, $FF82xx, jmp, nop...) changes
no RAM the picture depends on and is skipped; anything else unrecognised raises.
"""
import re
import struct

import capstone

MD = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
SKIP = re.compile(r'^(nop|exg|tst\.b|beq\.b|jmp|moveq|clr\.l d0)$|ff82|, a[01]$|, d0$')


def num(s):
    s = s.strip().lstrip('#')
    neg = s.startswith('-')
    s = s.lstrip('-').lstrip('$')
    v = int(s, 16)
    return -v if neg else v


def compile_program(code):
    """-> list of (op, args) closures-friendly tuples."""
    prog = []
    for ins in MD.disasm(code, 0):
        m, o = ins.mnemonic, ins.op_str
        if SKIP.search(f'{m} {o}'.strip()) or SKIP.search(m):
            continue
        prog.append((m, [a.strip() for a in split_ops(o)]))
    return prog


def split_ops(o):
    out, depth, cur = [], 0, ''
    for ch in o:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


class CPU:
    def __init__(self, mem):
        self.m = mem
        self.r = {f'd{i}': 0 for i in range(8)} | {f'a{i}': 0 for i in range(8)}

    def rd(self, a, n):
        return int.from_bytes(self.m[a:a + n], 'big')

    def wr(self, a, n, v):
        self.m[a:a + n] = (v & ((1 << (8 * n)) - 1)).to_bytes(n, 'big')

    def ea(self, s, n):
        """-> ('reg', name) | ('mem', addr). Applies (an)+ increments."""
        if re.fullmatch(r'[ad]\d', s):
            return ('reg', s)
        mm = re.fullmatch(r'\((a\d)\)\+', s)
        if mm:
            a = self.r[mm[1]]
            self.r[mm[1]] = a + n
            return ('mem', a)
        mm = re.fullmatch(r'(-?\$[0-9a-f]+)?\((a\d)\)', s)
        if mm:
            return ('mem', (self.r[mm[2]] + (num(mm[1]) if mm[1] else 0)) & 0xFFFFFF)
        mm = re.fullmatch(r'\$([0-9a-f]+)\.l', s)
        if mm:
            return ('mem', int(mm[1], 16))
        raise ValueError(s)

    def get(self, loc, n):
        if loc[0] == 'reg':
            return self.r[loc[1]] & ((1 << (8 * n)) - 1)
        return self.rd(loc[1], n)

    def put(self, loc, n, v):
        if loc[0] == 'reg':
            mask = (1 << (8 * n)) - 1
            self.r[loc[1]] = (self.r[loc[1]] & ~mask & 0xFFFFFFFF) | (v & mask)
        else:
            self.wr(loc[1], n, v)

    def run(self, prog):
        for m, ops in prog:
            self.step(m, ops)

    def step(self, m, ops):
        n = {'l': 4, 'w': 2, 'b': 1}[m[-1]] if '.' in m else 4
        base = m.split('.')[0]
        if base in ('move', 'movea'):
            src = self.get(self.ea(ops[0], n), n) if not ops[0].startswith('#') else num(ops[0])
            dst = self.ea(ops[1], n)
            if base == 'movea' and dst[0] == 'reg':
                self.r[dst[1]] = src & 0xFFFFFFFF
            else:
                self.put(dst, n, src)
        elif base == 'clr':
            self.put(self.ea(ops[0], n), n, 0)
        elif base in ('and', 'or'):
            s = self.get(self.ea(ops[0], n), n)
            d = self.ea(ops[1], n)
            v = self.get(d, n)
            self.put(d, n, (v & s) if base == 'and' else (v | s))
        elif base == 'adda':
            self.r[ops[1]] = (self.r[ops[1]] + self.get(self.ea(ops[0], n), n)) & 0xFFFFFFFF
        elif base == 'addq':
            self.r[ops[1]] = (self.r[ops[1]] + num(ops[0])) & 0xFFFFFFFF
        elif base == 'lea':
            self.r[ops[1]] = self.ea(ops[0], 4)[1]
        else:
            raise ValueError(f'{m} {ops}')


def menu_vbl_program():
    d = open('menu_td.bin', 'rb').read()
    frags = open('menu_frags.bin', 'rb').read()
    return compile_program(d[0xe10:0x15d2] + frags)


if __name__ == '__main__':
    p = menu_vbl_program()
    print(len(p), 'data instructions')
    print(sorted({m for m, _ in p}))
