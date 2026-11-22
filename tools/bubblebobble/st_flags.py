"""Which condition flags are LIVE after each instruction: a flag nothing reads before it is set again
need not be computed. A backward fixed point over the program's flow; any transfer the analysis
cannot follow (a call, a return, an indirect jump, a trap, an interrupt's rte) counts as reading
every flag, so the translation stays exact where it cannot prove otherwise.
"""
import st_ops
import st_prg

X, N, Z, V, C = 16, 8, 4, 2, 1
ALL = X | N | Z | V | C
NZVC = N | Z | V | C
USES = {'hi': C | Z, 'ls': C | Z, 'cc': C, 'cs': C, 'ne': Z, 'eq': Z, 'vc': V, 'vs': V, 'pl': N, 'mi': N,
        'ge': N | V, 'lt': N | V, 'gt': N | V | Z, 'le': N | V | Z}
OPAQUE = ('rts', 'rte', 'trap', 'bsr', 'jsr', 'jmp')


def defs_uses(i):
    """(flags the instruction always sets, flags it reads)."""
    base, _ = st_ops.split(i)
    if base in ('move', 'moveq', 'tst', 'clr', 'ext', 'swap', 'mulu') or base in st_ops.LOGIC:
        return NZVC, 0
    if base in ('cmp', 'cmpi', 'cmpa'):
        return NZVC, 0
    if base in st_ops.ALU:
        return (0, 0) if i.operands[-1].address_mode == 2 else (ALL, 0)
    if base in ('lsl', 'lsr', 'asl', 'asr'):
        reg_count = len(i.operands) == 2 and i.operands[0].address_mode == 1
        return (NZVC if reg_count else ALL), 0  # a count of 0 keeps X
    if base in ('roxl', 'roxr'):
        return (NZVC if len(i.operands) == 2 and i.operands[0].address_mode == 1 else ALL), X
    if base in st_ops.BITS:
        return Z, 0
    if base == 'addx':
        return X | N | V | C, X | Z
    if base == 'divu':
        return V | C, 0
    if base[0] == 'b' and base[1:] in USES:
        return 0, USES[base[1:]]
    return 0, 0


def successors(i, insns):
    base, _ = st_ops.split(i)
    tgt = st_prg.branch_target(i)
    if base == 'jmp' and tgt is not None:
        return [tgt] if tgt in insns else None
    if base in OPAQUE:
        return None
    out = []
    if base not in ('bra',):
        out.append(i.address + i.size)
    if tgt is not None and (base in ('bra', 'dbra') or base[1:] in USES):
        out.append(tgt)
    return [a for a in out if a in insns] if all(a in insns for a in out) else None


def live_after(insns):
    """{address: flags live after the instruction}."""
    du = {a: defs_uses(i) for a, i in insns.items()}
    succ = {a: successors(i, insns) for a, i in insns.items()}
    live_in = {a: 0 for a in insns}  # the least fixed point: grown from nothing
    changed = True
    while changed:
        changed = False
        for a in sorted(insns, reverse=True):
            out = ALL if succ[a] is None else 0
            for s in succ[a] or ():
                out |= live_in[s]
            d, u = du[a]
            new = (out & ~d) | u
            if new != live_in[a]:
                live_in[a] = new
                changed = True
    after = {}
    for a in insns:
        out = ALL if succ[a] is None else 0
        for s in succ[a] or ():
            out |= live_in[s]
        after[a] = out
    return after
