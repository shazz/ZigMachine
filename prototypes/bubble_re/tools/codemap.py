#!/usr/bin/env python3
"""BUBBLE.PRG code/data map by recursive descent (capstone, 68000).

    python3 prototypes/bubble_re/tools/codemap.py

Reads prototypes/bubble_re/files/BUBBLE.PRG, writes prototypes/bubble_re/work/:
  text.bin     the TEXT segment (relocated to base 0)
  relocs.txt   the relocation offsets (hex, one per line)
  code.lst     every decoded instruction reached from the entries, with labels
  codemap.txt  summary: code ranges, indirect jumps, unresolved targets, pointer tables
"""
import os
import struct
import sys

import capstone as cs

HERE = os.path.dirname(os.path.abspath(__file__))
RE = os.path.dirname(HERE)
WORK = os.path.join(RE, 'work')

# Exception/interrupt vectors the program installs ($70 VBL, $120 Timer B).
HANDLERS = [0x0EB0, 0x0F28, 0x0FA4, 0x0E84, 0x0F74, 0x0E96]
# Jump tables read by `movea.l (a1,d1.l),a2; jsr (a2)`: (address, entries).
TABLES = [(0x3D34, 115), (0x5A64, 115), (0x7692, 16)]


def load():
    d = open(os.path.join(RE, 'files', 'BUBBLE.PRG'), 'rb').read()
    magic, text, data, bss, sym = struct.unpack('>HIIII', d[:18])
    assert magic == 0x601A
    T = d[28:28 + text + data]
    r = 28 + text + data + sym
    relocs = []
    p = struct.unpack('>I', d[r:r + 4])[0]
    if p:
        relocs.append(p)
        i = r + 4
        while d[i]:
            p += 254 if d[i] == 1 else d[i]
            if d[i] != 1:
                relocs.append(p)
            i += 1
    return T, relocs


def main():
    T, relocs = load()
    os.makedirs(WORK, exist_ok=True)
    open(os.path.join(WORK, 'text.bin'), 'wb').write(T)
    open(os.path.join(WORK, 'relocs.txt'), 'w').write(''.join('%x\n' % x for x in relocs))
    md = cs.Cs(cs.CS_ARCH_M68K, cs.CS_MODE_BIG_ENDIAN | cs.CS_MODE_M68K_000)
    md.detail = True
    extra = [int(a, 16) for a in sys.argv[1:]]
    for t, n in TABLES:
        extra += [struct.unpack('>I', T[t + 4 * k:t + 4 * k + 4])[0] for k in range(n)]
    insns, labels, indirect, outside, bad = descend(md, T, [0] + HANDLERS + extra)
    write(T, relocs, insns, labels, indirect, outside, bad)


def descend(md, T, entries):
    insns, labels, indirect, outside, bad = {}, {}, [], set(), []
    todo = [(e, 'entry') for e in entries]
    while todo:
        pc, why = todo.pop()
        labels.setdefault(pc, why)
        while pc not in insns:
            if pc >= len(T) or pc & 1:
                bad.append((pc, why))
                break
            got = list(md.disasm(T[pc:pc + 10], pc, 1))
            if not got:
                bad.append((pc, why))
                break
            i = got[0]
            insns[pc] = i
            m = i.mnemonic
            tgt = branch_target(i)
            flow_ends = m in ('rts', 'rte', 'rtr', 'bra', 'jmp', 'bra.w', 'bra.s', 'bra.b')
            if tgt is not None:
                if tgt < len(T):
                    todo.append((tgt, 'call' if m.startswith(('jsr', 'bsr')) else 'jump'))
                else:
                    outside.add((tgt, pc))
            elif m.startswith(('jmp', 'jsr')):
                indirect.append(i)
            if flow_ends:
                break
            pc += i.size
    return insns, labels, indirect, outside, bad


def branch_target(i):
    m = i.mnemonic
    if not (m.startswith(('b', 'db', 'jmp', 'jsr')) and m not in ('bchg', 'bclr', 'bset', 'btst')
            and not m.startswith(('bchg', 'bclr', 'bset', 'btst'))):
        return None
    for o in i.operands:
        if o.type == cs.m68k.M68K_OP_BR_DISP:
            return i.address + 2 + o.br_disp.disp
        if o.type == cs.m68k.M68K_OP_MEM and o.address_mode in (cs.m68k.M68K_AM_ABSOLUTE_DATA_LONG,
                                                                cs.m68k.M68K_AM_ABSOLUTE_DATA_SHORT):
            return o.imm if hasattr(o, 'imm') and o.imm else o.mem.disp
    return None


def write(T, relocs, insns, labels, indirect, outside, bad):
    with open(os.path.join(WORK, 'code.lst'), 'w') as f:
        prev = None
        for a in sorted(insns):
            i = insns[a]
            if prev is not None and a != prev:
                f.write('        ; ---- gap $%x-$%x (%d bytes)\n' % (prev, a, a - prev))
            if a in labels:
                f.write('L%05x:  ; %s\n' % (a, labels[a]))
            f.write('  %05x  %-8s %s\n' % (a, i.mnemonic, i.op_str))
            prev = a + i.size
    code = set()
    for a, i in insns.items():
        code.update(range(a, a + i.size))
    ranges, start = [], None
    for a in range(len(T) + 1):
        if a in code and start is None:
            start = a
        if a not in code and start is not None:
            ranges.append((start, a))
            start = None
    with open(os.path.join(WORK, 'codemap.txt'), 'w') as f:
        f.write('instructions %d, code bytes %d of %d\n' % (len(insns), len(code), len(T)))
        f.write('labels %d (calls %d)\n' % (len(labels), sum(1 for v in labels.values() if v == 'call')))
        f.write('\nindirect jumps/calls:\n')
        for i in indirect:
            f.write('  %05x %s %s\n' % (i.address, i.mnemonic, i.op_str))
        f.write('\ncalls/jumps outside TEXT:\n')
        for t, pc in sorted(outside):
            f.write('  -> %x from %05x\n' % (t, pc))
        f.write('\nbad decodes:\n')
        for pc, why in bad:
            f.write('  %x (%s)\n' % (pc, why))
        f.write('\nreloc longs in data pointing into TEXT (candidate pointer tables):\n')
        for r in relocs:
            if r in code:
                continue
            v = struct.unpack('>I', T[r:r + 4])[0]
            if v < len(T):
                f.write('  @%05x -> %05x %s\n' % (r, v, 'CODE' if v in insns else ''))
        f.write('\ncode ranges:\n')
        for s, e in ranges:
            f.write('  %05x-%05x %d\n' % (s, e, e - s))


if __name__ == '__main__':
    main()
