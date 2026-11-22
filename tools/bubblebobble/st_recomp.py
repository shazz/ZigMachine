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
rts pops it, so the game's stack tricks (the main loop resets SP) work as they did. Each straight
run of instructions adds its approximate 68000 cycles to k.cy (the clock the interrupts are timed
on) once, before the instruction that can leave it.
Generated code: the 200-line/30-line rules apply to this generator, not to its output.
"""
import bisect
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import st_ops  # noqa: E402
import st_prg  # noqa: E402
import st_flags  # noqa: E402
from st_cycles import cycles  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('BUBBLE_RE', '/home/matt/projects/ZigMachine/prototypes/bubble_re')
OUT = os.path.join(ROOT, 'apps', 'zig', 'scenes', 'bubblebobble', 'gen')
ROUTINE_STARTS = ('entry', 'irq', 'callback', 'table', 'call')
FILE_LINES = 1500
POLL = ('tst', 'cmp', 'cmpi', 'btst')
# The sound driver (TEXT $A7AE-$AF90) and the two entries the game calls it by: a call from outside
# the driver tells the host (k.hook), which plays the same request on the game's SNDH.
DRIVER = (st_prg.BASE + 0xA7AE, st_prg.BASE + 0xAF90)
HOOKS = {st_prg.BASE + 0xA7AE, st_prg.BASE + 0xAC12}  # start tune $AC06, start effect $AC10


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
        self.after = st_flags.live_after(insns)

    def live(self, i):
        """The flags this instruction sets that a later one reads."""
        return self.after[i.address] & st_flags.defs_uses(i)[0]

    def target(self, i):
        return st_prg.branch_target(i)

    def jump(self, tgt, i):
        if tgt in self.chunk.labels:
            if tgt <= i.address:
                return '{ if (k.cy >= k.limit) return 0x%x; continue :sw 0x%x; }' % (tgt, tgt)
            return 'continue :sw 0x%x;' % tgt
        return 'return 0x%x;' % tgt

    def call(self, tgt, ret, i):
        """A call to another routine is a native call (its rts returns `ret`); anything else it
        returns -- a stop at the frame's end, a stack trick -- goes back to the dispatcher, and the
        return address is still on the 68000's stack for when the dispatcher gets there."""
        if tgt in self.chunk.labels:
            return self.jump(tgt, i)
        back = ('continue :sw 0x%x;' % ret) if ret in self.chunk.labels else ('return 0x%x;' % ret)
        return '{ const p = @@CALL(0x%x)@@; if (p != 0x%x) return p; %s }' % (tgt, ret, back)

    def hooked(self, i, tgt):
        return tgt in HOOKS and not DRIVER[0] <= i.address < DRIVER[1]

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
        out = ['pub noinline fn run(pc: u32) u32 {', '    sw: switch (pc) {']
        open_case = False
        pending = 0
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
            # the cycles of a straight run are added once, before the instruction that can leave it
            pending += cycles(i)
            nxt = a + i.size
            leaves = transfers(i) or n + 1 == len(chunk.addrs) or nxt in chunk.labels or \
                chunk.addrs[n + 1] != nxt
            body = (['k.cy +%%= %d;' % pending] if leaves else []) + st_ops.gen(i, self)
            if leaves:
                pending = 0
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


def transfers(i):
    """An instruction that can leave the straight run: a branch, call, return or trap."""
    base = i.mnemonic.split('.')[0]
    return base in ('bra', 'jmp', 'rts', 'rte', 'trap', 'bsr', 'jsr', 'dbra') or \
        (base[0] == 'b' and base[1:] in st_ops.COND)


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
    data = bytearray(prg.image)  # the TEXT's data only: every translated instruction's bytes zeroed
    for a, i in insns.items():
        data[a - st_prg.BASE:a - st_prg.BASE + i.size] = bytes(i.size)
    with open(os.path.join(RE, 'work', 'text_data.bin'), 'wb') as f:
        f.write(data)


HEADER = ('// GENERATED by tools/bubblebobble/st_recomp.py from BUBBLE.PRG -- do not edit.\n'
          '// The 68000 code of Bubble Bobble (Firebird 1987), instruction for instruction:\n'
          '// each comment is the original instruction at its TEXT offset.\n'
          'const k = @import("../st/cpu.zig");\n\n')


def write(files, insns):
    disp = [HEADER]
    home = {ch.start: chunks_[0][0].start for chunks_ in files for ch, _ in chunks_}
    imports = ''.join('const f%05x = @import("c%05x.zig");\n' % (f[0][0].start, f[0][0].start) for f in files)

    starts = sorted(home)

    def call(m):  # the routine holding the target (a call can land inside one)
        t = int(m.group(1), 16)
        c = starts[bisect.bisect_right(starts, t) - 1]
        return 'f%05x.c%05x.run(0x%x)' % (home[c], c, t)

    for chunks_ in files:
        fname = 'c%05x.zig' % chunks_[0][0].start
        with open(os.path.join(OUT, fname), 'w') as f:
            f.write(HEADER + imports + '\n')
            for ch, body in chunks_:
                f.write('pub const %s = struct {\n' % ch.name())
                text = ''.join('    ' + line + '\n' if line else '\n' for line in body)
                f.write(re.sub(r'@@CALL\(0x([0-9a-f]+)\)@@', call, text))
                f.write('};\n\n')
        disp.append('const f%05x = @import("%s");\n' % (chunks_[0][0].start, fname))
    routines = [(ch, chunks_[0][0].start) for chunks_ in files for ch, _ in chunks_]
    disp.append('\n/// Each routine\'s TEXT range (first instruction to its last), in address order.\n')
    disp.append('const RANGES = [_][2]u32{\n')
    for ch, _ in routines:
        disp.append('    .{ 0x%x, 0x%x },\n' % (ch.start, ch.addrs[-1]))
    disp.append('};\n')
    disp.append('''const BASE: u32 = 0x%x;
/// (pc - BASE) / 2 -> the routine holding it (0xFFFF: none), built at compile time.
const ROUTE = blk: {
    @setEvalBranchQuota(200000);
    var t = [_]u16{0xFFFF} ** (0x%x / 2);
    for (RANGES, 0..) |r, n| {
        var a = r[0];
        while (a <= r[1]) : (a += 2) t[(a - BASE) / 2] = n;
    }
    break :blk t;
};

/// The routine that holds `pc`, run from `pc` until control leaves it.
pub fn dispatch(pc: u32) u32 {
    const i = (pc -%% BASE) / 2;
    if (i >= ROUTE.len) return k.bad(pc);
    return switch (ROUTE[i]) {
''' % (st_prg.BASE, max(insns) + 2 - st_prg.BASE))
    for n, (ch, f) in enumerate(routines):
        disp.append('        %d => f%05x.%s.run(pc),\n' % (n, f, ch.name()))
    disp.append('        else => k.bad(pc),\n    };\n}\n')
    with open(os.path.join(OUT, 'dispatch.zig'), 'w') as f:
        f.write(''.join(disp))
    print('%d instructions, %d files' % (len(insns), len(files)))


if __name__ == '__main__':
    main()
