"""Approximate 68000 cycles of an instruction (the clock the cart times the interrupts on).

Not cycle-exact: 4 cycles a program word, 4 a memory byte/word access (8 a long), plus the
documented extras of the slow instructions. Good to a few percent over a frame, which is what
decides how many VBLs a pass of the game's loop takes.
"""
from st_ops import split

EXTRA = {'mulu': 54, 'divu': 136, 'dbra': 6, 'bsr': 10, 'jsr': 8, 'rts': 12, 'rte': 16,
         'trap': 30, 'lea': -2, 'clr': 0}


def cycles(i):
    base, size = split(i)
    words = i.size // 2
    n = 4 * words
    mem_ops = sum(1 for o in i.operands if o.address_mode not in (0, 1, 2, 18, 19))
    per = 8 if size == 4 else 4
    if base == 'movem':
        cnt = bin(next(o.register_bits for o in i.operands if o.type == 6)).count('1')
        return n + 4 + 8 * cnt
    if base in ('lea', 'pea'):
        return n + (4 if base == 'pea' else 0)
    n += mem_ops * per
    if base in ('move', 'movea') and mem_ops == 0 and words == 1:
        n = 4
    if base in ('asl', 'asr', 'lsl', 'lsr', 'roxl', 'roxr'):
        o = i.operands[0]
        n += 2 + 2 * (o.imm if o.address_mode == 18 else 4)
    if base in ('bsr', 'jsr', 'rts', 'rte', 'trap'):
        n += 8  # the stacked return address
    if base[0] == 'b' and base not in ('btst', 'bset', 'bclr', 'bchg'):
        n += 6
    return n + EXTRA.get(base, 0)
