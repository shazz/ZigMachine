"""BUBBLE.PRG (Firebird 1987, the Atari ST game): the program, relocated, and its code map.

The TEXT segment is relocated to BASE, as TOS would load it, and walked by recursive descent from
the entry, the interrupt handlers the program installs, the TOS callbacks it registers and its
jump tables: every instruction reached is code, everything else is data (the game keeps its
variables, tables and texts between its routines).
"""
import os
import struct

import capstone as cs

# Where the cart loads the TEXT segment. The game uses absolute RAM from $1EE76 up (MUSIC.DAT,
# AIRFLOW.DAT, BDATA.DAT, the sprite banks) without relocating it, so TEXT ($E206 bytes) must end
# below $1EE76; the real TOS loads it lower still, which no instruction can tell apart.
BASE = 0x10000

# Interrupt handlers the program installs: $70 (VBL) and $120 (MFP Timer B).
HANDLERS = [0x0EB0, 0x0F28, 0x0FA4, 0x0E84, 0x0F74, 0x0E96]
# Kbdvbase callbacks it registers: joyvec $3C86 (the joystick packet), mousevec $3CA0 (an rts).
CALLBACKS = [0x3C86, 0x3CA0]
# Jump tables read as `movea.l (a1,d1.l),a2; jsr (a2)`: (TEXT offset, entries).
TABLES = [(0x3D34, 115), (0x5A64, 115), (0x7692, 16)]


class Prg:
    def __init__(self, path):
        d = open(path, 'rb').read()
        magic, text, data, bss, sym = struct.unpack('>HIIII', d[:18])
        assert magic == 0x601A, 'not a GEMDOS program'
        self.text_len = text + data
        img = bytearray(d[28:28 + self.text_len])
        r = 28 + self.text_len + sym
        self.relocs = []
        p = struct.unpack('>I', d[r:r + 4])[0]
        if p:
            self.relocs.append(p)
            i = r + 4
            while d[i]:
                p += 254 if d[i] == 1 else d[i]
                if d[i] != 1:
                    self.relocs.append(p)
                i += 1
        for o in self.relocs:
            v = struct.unpack('>I', img[o:o + 4])[0]
            img[o:o + 4] = struct.pack('>I', v + BASE)
        self.image = bytes(img)

    def long(self, off):
        return struct.unpack('>I', self.image[off:off + 4])[0]

    def entries(self):
        e = [(0, 'entry')] + [(h, 'irq') for h in HANDLERS] + [(c, 'callback') for c in CALLBACKS]
        for t, n in TABLES:
            e += [(self.long(t + 4 * k) - BASE, 'table') for k in range(n)]
        return [(BASE + o, why) for o, why in e]


def disassembler():
    md = cs.Cs(cs.CS_ARCH_M68K, cs.CS_MODE_BIG_ENDIAN | cs.CS_MODE_M68K_000)
    md.detail = True
    return md


def branch_target(i):
    """The static target of a branch, bsr, jsr or jmp, or None (indirect / not a branch)."""
    for o in i.operands:
        if o.type == cs.m68k.M68K_OP_BR_DISP:
            return i.address + 2 + o.br_disp.disp
    if i.mnemonic in ('jsr', 'jmp'):
        o = i.operands[0]
        if o.address_mode in (16, 17):
            return o.imm
        if o.address_mode == 11:
            return i.address + 2 + o.mem.disp
    return None


FLOW_END = ('rts', 'rte', 'bra', 'jmp')


def descend(prg, md):
    """Every instruction reached from the entries: {address: insn}, {label: why}."""
    insns, labels = {}, {}
    todo = list(prg.entries())
    end = BASE + prg.text_len
    while todo:
        pc, why = todo.pop()
        labels.setdefault(pc, why)
        while pc not in insns:
            assert BASE <= pc < end and not pc & 1, 'flow leaves TEXT at $%x (%s)' % (pc, why)
            i = next(md.disasm(prg.image[pc - BASE:pc - BASE + 10], pc, 1))
            insns[pc] = i
            base = i.mnemonic.split('.')[0]
            tgt = branch_target(i) if base.startswith(('b', 'db', 'j')) else None
            if tgt is not None and base not in ('bset', 'bclr', 'bchg', 'btst'):
                todo.append((tgt, 'call' if base in ('bsr', 'jsr') else 'jump'))
            if base in ('bsr', 'jsr', 'trap'):
                todo.append((pc + i.size, 'return'))
            if base in FLOW_END:
                break
            pc += i.size
    return insns, labels


def load(re_dir):
    prg = Prg(os.path.join(re_dir, 'files', 'BUBBLE.PRG'))
    insns, labels = descend(prg, disassembler())
    return prg, insns, labels
