"""68000 operands as Zig: the register, the effective address computed once, the read and the write.

The generated code addresses the machine through `k` (apps/zig/scenes/bubblebobble/st/cpu.zig):
k.d[0..8] / k.a[0..8] the registers, k.rb/rw/rl and k.wb/ww/wl the bus.
"""
from capstone import m68k as M

TYPES = {1: 'u8', 2: 'u16', 4: 'u32'}
READ = {1: 'k.rb', 2: 'k.rw', 4: 'k.rl'}
WRITE = {1: 'k.wb', 2: 'k.ww', 4: 'k.wl'}
MASK = {1: 0xFF, 2: 0xFFFF, 4: 0xFFFFFFFF}


def reg(r):
    """A capstone register id as ('d'|'a', n)."""
    if M.M68K_REG_D0 <= r <= M.M68K_REG_D7:
        return 'd', r - M.M68K_REG_D0
    if M.M68K_REG_A0 <= r <= M.M68K_REG_A7:
        return 'a', r - M.M68K_REG_A0
    raise ValueError('register %d' % r)


def index(o):
    """The index term of a d8(An,Xn) / d8(PC,Xn) operand."""
    kind, n = reg(o.mem.index_reg)
    r = 'k.%s[%d]' % (kind, n)
    return r if o.mem.index_size == 1 else 'k.sx16(@truncate(%s))' % r


class Operand:
    """One operand of size `size` bytes; `ext` is the address of its extension words (PC-relative)."""

    def __init__(self, o, size, ext, tmp):
        self.o, self.size, self.ext, self.tmp = o, size, ext, tmp
        self.am = o.address_mode
        self.t = TYPES.get(size)

    def is_reg(self, kind=None):
        if self.am == 1:
            return kind in (None, 'd')
        return self.am == 2 and kind in (None, 'a')

    def regno(self):
        return reg(self.o.reg)[1]

    def is_mem(self):
        return self.am not in (1, 2, 18)

    def is_io(self):
        return self.am in (16, 17) and (self.o.imm & 0xFFFFFF) >= 0xFF8000

    def addr(self):
        """(statements, expression): the effective address, side effects done once."""
        am, o, v = self.am, self.o, self.tmp
        if am == 3:
            return [], 'k.a[%d]' % reg(o.reg)[1]
        if am in (4, 5):
            n = reg(o.reg)[1]
            inc = 2 if (self.size == 1 and n == 7) else self.size
            if am == 4:
                return ['const %s = k.a[%d];' % (v, n), 'k.a[%d] +%%= %d;' % (n, inc)], v
            return ['k.a[%d] -%%= %d;' % (n, inc), 'const %s = k.a[%d];' % (v, n)], v
        if am == 6:
            return [], 'k.a[%d] +%% %s' % (reg(o.mem.base_reg)[1], disp32(o.mem.disp))
        if am in (7, 8):
            base = 'k.a[%d]' % reg(o.mem.base_reg)[1]
            return [], '%s +%% %s +%% %s' % (base, disp32(o.mem.disp), index(o))
        if am in (16, 17):
            return [], '0x%x' % (o.imm & 0xFFFFFF)
        if am == 11:
            return [], '0x%x' % ((self.ext + o.mem.disp) & 0xFFFFFF)
        if am == 12:
            return [], '@as(u32, 0x%x) +%% %s' % ((self.ext + o.mem.disp) & 0xFFFFFF, index(o))
        raise ValueError('no address for mode %d' % am)

    def bind(self):
        """Statements that fix the address in the operand's temp (a read-modify-write)."""
        if not self.is_mem():
            return []
        pre, e = self.addr()
        if e != self.tmp:
            pre = pre + ['const %s: u32 = %s;' % (self.tmp, e)]
        self.bound = self.tmp
        return pre

    def get(self):
        am, o = self.am, self.o
        if am == 1:
            return 'k.dv(%s, %d)' % (self.t, self.regno())
        if am == 2:
            return 'k.av(%s, %d)' % (self.t, self.regno())
        if am == 18:
            return '@as(%s, 0x%x)' % (self.t, o.imm & MASK[self.size])
        return '%s(%s)' % (READ[self.size], self.bound)

    def put(self, val):
        am = self.am
        if am == 1:
            return 'k.setD(%s, %d, %s);' % (self.t, self.regno(), val)
        if am == 2:
            return 'k.a[%d] = %s;' % (self.regno(), val)
        return '%s(%s, %s);' % (WRITE[self.size], self.bound, val)


def disp32(d):
    return '@as(u32, %d)' % d if d >= 0 else '@as(u32, @bitCast(@as(i32, %d)))' % d
