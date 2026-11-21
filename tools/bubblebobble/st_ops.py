"""One 68000 instruction as Zig statements (the instruction set BUBBLE.PRG uses, and no more).

`ctx` is the emitter: ctx.jump(target, here) is the statement that transfers control to a label
(a `continue :sw` inside the chunk, a `return` to the dispatcher outside it), ctx.idle(i) says the
branch closes a loop that only polls RAM (the frame waits).
"""
from st_ea import TYPES, Operand

SIZES = {'b': 1, 'w': 2, 'l': 4}
COND = {
    'hi': '!k.fc and !k.fz', 'ls': 'k.fc or k.fz', 'cc': '!k.fc', 'cs': 'k.fc', 'ne': '!k.fz',
    'eq': 'k.fz', 'vc': '!k.fv', 'vs': 'k.fv', 'pl': '!k.fneg', 'mi': 'k.fneg', 'ge': 'k.fneg == k.fv',
    'lt': 'k.fneg != k.fv', 'gt': '!k.fz and k.fneg == k.fv', 'le': 'k.fz or k.fneg != k.fv',
}
ALU = {'add': 'k.add', 'addi': 'k.add', 'addq': 'k.add', 'sub': 'k.sub', 'subi': 'k.sub',
       'subq': 'k.sub'}
LOGIC = {'and': '&', 'andi': '&', 'or': '|', 'ori': '|', 'eor': '^', 'eori': '^'}
SHIFT = ('asl', 'asr', 'lsl', 'lsr', 'roxl', 'roxr', 'rol', 'ror')
BITS = ('btst', 'bset', 'bclr', 'bchg')


def split(i):
    base, _, sfx = i.mnemonic.partition('.')
    return base, SIZES.get(sfx, 4)


def operands(i, size):
    return [Operand(o, size, i.address + 2, 'e%d' % n) for n, o in enumerate(i.operands)]


def sx(op, size):
    """An operand read as a u32, sign-extended (address arithmetic)."""
    v = op.get()
    if size == 2:
        return 'k.sx16(%s)' % v
    if size == 1:
        return 'k.sx8(%s)' % v
    return v


def gen(i, ctx):
    base, size = split(i)
    ops = operands(i, size)
    t = TYPES.get(size)
    nxt = i.address + i.size
    if base == 'move':
        return ops[0].bind() + ['const v = %s;' % ops[0].get()] + ops[1].bind() + \
            [ops[1].put('v'), 'k.logic(%s, v);' % t]
    if base == 'movea':
        return ops[0].bind() + [ops[1].put(sx(ops[0], size))]
    if base == 'movem':
        return movem(ops, size)
    if base == 'lea':
        pre, e = ops[0].addr()
        return pre + [ops[1].put(e)]
    if base == 'pea':
        pre, e = ops[0].addr()
        return pre + ['k.push32(%s);' % e]
    if base == 'clr':
        return ops[0].bind() + [ops[0].put('0'), 'k.logic(%s, 0);' % t]
    if base == 'tst':
        return ops[0].bind() + ['k.logic(%s, %s);' % (t, ops[0].get())]
    if base in ('cmp', 'cmpi'):
        return ops[0].bind() + ['const s = %s;' % ops[0].get()] + ops[1].bind() + \
            ['k.cmp(%s, s, %s);' % (t, ops[1].get())]
    if base == 'cmpa':
        return ops[0].bind() + ['k.cmp(u32, %s, k.a[%d]);' % (sx(ops[0], size), ops[1].regno())]
    if base in ALU or base in ('adda', 'suba'):
        return alu(base, ops, size, t)
    if base in LOGIC:
        return ops[0].bind() + ['const s = %s;' % ops[0].get()] + ops[1].bind() + \
            ['const r = %s %s s;' % (ops[1].get(), LOGIC[base]), ops[1].put('r'), 'k.logic(%s, r);' % t]
    if base == 'ext':
        n = ops[0].regno()
        if size == 2:
            return ['const r: u16 = @truncate(k.sx8(k.dv(u8, %d)));' % n, 'k.setD(u16, %d, r);' % n,
                    'k.logic(u16, r);']
        return ['k.d[%d] = k.sx16(k.dv(u16, %d));' % (n, n), 'k.logic(u32, k.d[%d]);' % n]
    if base == 'swap':
        n = ops[0].regno()
        return ['k.d[%d] = (k.d[%d] << 16) | (k.d[%d] >> 16);' % (n, n, n), 'k.logic(u32, k.d[%d]);' % n]
    if base in SHIFT:
        return shift(base, ops, t)
    if base == 'mulu':
        n = ops[1].regno()
        return ops[0].bind() + ['k.d[%d] = @as(u32, k.dv(u16, %d)) * @as(u32, %s);' % (n, n, ops[0].get()),
                                'k.logic(u32, k.d[%d]);' % n]
    if base == 'divu':
        return ops[0].bind() + ['k.divu(%d, %s);' % (ops[1].regno(), ops[0].get())]
    if base in BITS:
        return bits(base, ops)
    if base == 'addx':
        x, y = ops[1].regno(), ops[0].regno()
        return ['k.setD(u8, %d, k.addx(u8, k.dv(u8, %d), k.dv(u8, %d)));' % (x, y, x)]
    return flow(i, base, ops, ctx, nxt)


def alu(base, ops, size, t):
    dst = ops[1]
    if dst.is_reg('a') and dst.am == 2:
        op = '+%=' if base.startswith('add') else '-%='
        return ops[0].bind() + ['k.a[%d] %s %s;' % (dst.regno(), op, sx(ops[0], size))]
    return ops[0].bind() + ['const s = %s;' % ops[0].get()] + dst.bind() + \
        ['const r = %s(%s, s, %s);' % (ALU[base], t, dst.get()), dst.put('r')]


def shift(base, ops, t):
    if len(ops) == 1:  # memory, one bit, a word
        return ops[0].bind() + ['%s' % ops[0].put('k.%s(u16, %s, 1)' % (base, ops[0].get()))]
    cnt, dst = ops
    n = ('k.d[%d] & 63' % cnt.regno()) if cnt.am == 1 else '%d' % cnt.o.imm
    return [dst.put('k.%s(%s, %s, %s)' % (base, t, dst.get(), n))]


def bits(base, ops):
    b, dst = ops
    num = ('k.d[%d]' % b.regno()) if b.am == 1 else '%d' % b.o.imm
    if dst.am == 1:
        n = dst.regno()
        if base == 'btst':
            return ['k.btst(u32, k.d[%d], %s);' % (n, num)]
        return ['k.d[%d] = k.%s(u32, k.d[%d], %s);' % (n, base, n, num)]
    pre = dst.bind()
    if base == 'btst':
        return pre + ['k.btst(u8, %s, %s);' % (dst.get(), num)]
    return pre + [dst.put('k.%s(u8, %s, %s)' % (base, dst.get(), num))]


def movem(ops, size):
    if ops[0].o.type == 6:  # registers to memory
        regs, mem = ops[0].o.register_bits, ops[1]
        order = [r for r in range(16) if regs >> r & 1]
        assert size == 4, 'movem.w'
        if mem.am == 5:  # -(An): d0 ends at the lowest address, An at the block
            n = mem.regno()
            return ['const m = k.a[%d] -%% %d;' % (n, 4 * len(order)), 'k.a[%d] = m;' % n] + \
                   ['k.wl(m +%% %d, %s);' % (4 * j, regname(r)) for j, r in enumerate(order)]
        pre, e = mem.addr()
        return pre + ['const m: u32 = %s;' % e] + \
            ['k.wl(m +%% %d, %s);' % (4 * j, regname(r)) for j, r in enumerate(order)]
    mem, regs = ops[0], ops[1].o.register_bits
    order = [r for r in range(16) if regs >> r & 1]
    if mem.am == 4:
        n = mem.regno()
        out = ['const m = k.a[%d];' % n, 'k.a[%d] +%%= %d;' % (n, 4 * len(order))]
    else:
        pre, e = mem.addr()
        out = pre + ['const m: u32 = %s;' % e]
    return out + ['%s = k.rl(m +%% %d);' % (regname(r), 4 * j) for j, r in enumerate(order)]


def regname(r):
    return 'k.%s[%d]' % ('d' if r < 8 else 'a', r & 7)


def flow(i, base, ops, ctx, nxt):
    if base == 'bra':
        return [ctx.jump(ctx.target(i), i)]
    if base in ('bsr', 'jsr'):
        tgt = ctx.target(i)
        if tgt is None:
            pre, e = ops[0].addr()
            return pre + ['const t: u32 = %s;' % e, 'k.push32(0x%x);' % nxt, 'return t;']
        return ['k.push32(0x%x);' % nxt, ctx.jump(tgt, i)]
    if base == 'jmp':
        tgt = ctx.target(i)
        if tgt is None:
            pre, e = ops[0].addr()
            return pre + ['return %s;' % e]
        return [ctx.jump(tgt, i)]
    if base == 'rts':
        return ['return k.pop32();']
    if base == 'rte':
        return ['return k.rte();']
    if base == 'trap':
        return ['return k.trap(%d, 0x%x);' % (ops[0].o.imm, nxt)]
    if base == 'dbra':
        n = ops[0].regno()
        return ['const w = k.dv(u16, %d) -%% 1;' % n, 'k.setD(u16, %d, w);' % n,
                'if (w != 0xFFFF) %s' % ctx.jump(ctx.target(i), i)]
    if base.startswith('b') and base[1:] in COND:
        tgt = ctx.target(i)
        stmt = ctx.jump(tgt, i)
        if ctx.idle(i):
            stmt = '{ k.idle(); %s }' % stmt
        return ['if (%s) %s' % (COND[base[1:]], stmt)]
    raise ValueError('unhandled instruction at $%x: %s %s' % (i.address, i.mnemonic, i.op_str))
