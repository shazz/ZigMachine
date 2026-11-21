#!/usr/bin/env python3
"""BUBBLE BOBBLE (Firebird 1987): BUBBLE.PRG's 68000 code, translated to Zig, instruction for instruction.

    python3 tools/bubblebobble/st_recomp.py

Reads $BUBBLE_RE/files/BUBBLE.PRG (default prototypes/bubble_re in the main checkout), writes
apps/zig/scenes/bubblebobble/gen/: one file per run of routines (c_XXXXX.zig, each routine a
labelled switch over its labels: a branch inside it is a `continue`, any other transfer returns the
target address to dispatch.zig), dispatch.zig (address -> routine) and map.txt.

The translation is mechanical and complete: every instruction the program can reach (st_prg.py's
descent) becomes the statements of st_ops.py over the machine of ../st/cpu.zig (the registers,
the flags, the bus). Control flow keeps the 68000's own stack: bsr/jsr push the return address,
rts pops it, so the game's stack tricks (the main loop resets SP) work as they did. Each
instruction adds its approximate 68000 cycles to k.cy, the clock the interrupts are timed on.
Generated code: the 200-line/30-line rules apply to this generator, not to its output.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import st_ops  # noqa: E402
import st_prg  # noqa: E402
from st_cycles import cycles  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('BUBBLE_RE', '/home/matt/projects/ZigMachine/prototypes/bubble_re')
OUT = os.path.join(ROOT, 'apps', 'zig', 'scenes', 'bubblebobble', 'gen')
ROUTINE_STARTS = ('entry', 'irq', 'callback', 'table', 'call')
FILE_LINES = 1500
POLL = ('tst', 'cmp', 'cmpi', 'btst')


class Chunk:
    def __init__(self, start, end, insns, labels):
        self.start, self.end = start, end
        self.addrs = [a for a in sorted(insns) if start <= a < end]
        self.labels = {a for a in labels if start <= a < end}

    def name(self):
        return 'c%05x' % self.start


class Emitter:
    def __init__(self, insns, labels):
        self.insns, self.labels = insns, labels
        self.chunk = None

    def target(self, i):
        return st_prg.branch_target(i)

    def jump(self, tgt, i):
        if tgt in self.chunk.labels:
            if tgt <= i.address:
                return '{ if (k.cy >= k.limit) return 0x%x; continue :sw 0x%x; }' % (tgt, tgt)
            return 'continue :sw 0x%x;' % tgt
        return 'return 0x%x;' % tgt

    def idle(self, i):
        tgt = self.target(i)
        if tgt is None or tgt > i.address or i.address - tgt > 24:
            return False
        a = tgt
        while a < i.address:
            j = self.insns.get(a)
            if j is None or j.mnemonic.split('.')[0] not in POLL:
                return False
            if any(st_ops.Operand(o, 1, 0, '').is_io() for o in j.operands):
                return False
            a += j.size
        return True

    def emit(self, chunk):
        self.chunk = chunk
        out = ['pub fn run(pc: u32) u32 {', '    sw: switch (pc) {']
        open_case = False
        for n, a in enumerate(chunk.addrs):
            i = self.insns[a]
            if a in chunk.labels:
                if open_case:
                    out.append('            continue :sw 0x%x;' % a)
                    out.append('        },')
                out.append('        0x%x => {' % a)
                open_case = True
            elif not open_case:
                raise ValueError('instruction $%x not reached from a label' % a)
            out.append('            // $%05x  %s %s' % (a - st_prg.BASE, i.mnemonic, i.op_str))
            body = ['k.cy +%%= %d;' % cycles(i)] + st_ops.gen(i, self)
            out.append('            {')
            out += ['                ' + s for s in body]
            out.append('            }')
            if ends(i):
                out.append('        },')
                open_case = False
            elif n + 1 == len(chunk.addrs) or chunk.addrs[n + 1] != a + i.size:
                if a + i.size not in self.insns:
                    raise ValueError('flow falls off $%x' % a)
                out.append('            return 0x%x; // falls into the next routine' % (a + i.size))
                out.append('        },')
                open_case = False
        if open_case:
            raise ValueError('chunk %s ends open' % chunk.name())
        out += ['        else => return k.bad(pc),', '    }', '}', '']
        if not any('continue :sw' in line for line in out):
            out[1] = '    switch (pc) {'
        return out


def ends(i):
    base = i.mnemonic.split('.')[0]
    return base in ('bra', 'jmp', 'rts', 'rte', 'trap', 'bsr', 'jsr')


def chunks(insns, labels):
    starts = sorted(a for a, why in labels.items() if why in ROUTINE_STARTS)
    bounds = starts + [max(insns) + 1]
    return [Chunk(s, e, insns, labels) for s, e in zip(bounds, bounds[1:])]


def main():
    prg, insns, labels = st_prg.load(RE)
    # every instruction after a flow end that is reached only by falling through needs no label;
    # every one reached by a jump has one. Calls return to the next instruction: a label too.
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.zig'):
            os.remove(os.path.join(OUT, f))
    em = Emitter(insns, labels)
    files, cur, size = [], [], 0
    for ch in chunks(insns, labels):
        body = em.emit(ch)
        if cur and size + len(body) > FILE_LINES:
            files.append(cur)
            cur, size = [], 0
        cur.append((ch, body))
        size += len(body)
    files.append(cur)
    write(files, insns)
    with open(os.path.join(RE, 'work', 'text_reloc.bin'), 'wb') as f:
        f.write(prg.image)


HEADER = ('// GENERATED by tools/bubblebobble/st_recomp.py from BUBBLE.PRG -- do not edit.\n'
          '// The 68000 code of Bubble Bobble (Firebird 1987), instruction for instruction:\n'
          '// each comment is the original instruction at its TEXT offset.\n'
          'const k = @import("../st/cpu.zig");\n\n')


def write(files, insns):
    disp = [HEADER.replace('const k', 'const k'), ]
    for chunks_ in files:
        fname = 'c%05x.zig' % chunks_[0][0].start
        with open(os.path.join(OUT, fname), 'w') as f:
            f.write(HEADER)
            for ch, body in chunks_:
                f.write('pub const %s = struct {\n' % ch.name())
                f.write(''.join('    ' + line + '\n' if line else '\n' for line in body))
                f.write('};\n\n')
        disp.append('const f%05x = @import("%s");\n' % (chunks_[0][0].start, fname))
    disp.append('\n/// The routine that holds `pc`, run from `pc` until control leaves it.\n')
    disp.append('pub fn dispatch(pc: u32) u32 {\n    return switch (pc) {\n')
    for chunks_ in files:
        for ch, _ in chunks_:
            disp.append('        0x%x...0x%x => f%05x.%s.run(pc),\n' % (
                ch.start, ch.addrs[-1], chunks_[0][0].start, ch.name()))
    disp.append('        else => k.bad(pc),\n    };\n}\n')
    with open(os.path.join(OUT, 'dispatch.zig'), 'w') as f:
        f.write(''.join(disp))
    print('%d instructions, %d files' % (len(insns), len(files)))


if __name__ == '__main__':
    main()
