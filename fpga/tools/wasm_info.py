"""What the native host needs to know about a wasm module before it runs it.

`high_water` is a line-for-line port of `cartHighWater` in docs/wasm_hiwater.js,
including its 32-bit LEB arithmetic, because the value it returns is what the JS
host hands to hwSetCartHigh / hwSetRomHigh and the machine answers hwRamFree from
it. `memory_import` reads the `env.memory` limits so the generator can refuse a
module the JS host would refuse with a LinkError.
"""

MASK = 0xFFFFFFFF


def _uleb(b: bytes, p: int) -> tuple[int, int]:
    r = s = 0
    while True:
        x = b[p]
        p += 1
        r = (r | ((x & 0x7F) << (s % 32))) & MASK  # JS `<<` shifts mod 32 on int32
        s += 7
        if not x & 0x80:
            return r, p


def _sleb(b: bytes, p: int) -> tuple[int, int]:
    r = s = 0
    while True:
        x = b[p]
        p += 1
        r = (r | ((x & 0x7F) << (s % 32))) & MASK
        s += 7
        if not x & 0x80:
            break
    if s < 32 and x & 0x40:
        r = (r | (MASK << s)) & MASK
    return r, p


def _init_expr(b: bytes, p: int) -> tuple[int | None, int]:
    """One constant initialiser: its i32 value (as unsigned) or None, and the next offset."""
    v = None
    if b[p] == 0x41:  # i32.const
        v, p = _sleb(b, p + 1)
    while b[p] != 0x0B:  # tolerate anything else, as the JS does
        p += 1
    return v, p + 1


def _sections(b: bytes):
    if b[:4] != b"\0asm":
        raise ValueError("not a wasm module")
    p = 8
    while p < len(b):
        sid = b[p]
        size, p = _uleb(b, p + 1)
        yield sid, p
        p += size


def _globals_high(b: bytes, p: int, high: int | None) -> int | None:
    n, p = _uleb(b, p)
    for _ in range(n):
        vtype, mutable = b[p], b[p + 1]
        v, p = _init_expr(b, p + 2)
        if vtype == 0x7F and mutable == 1 and v is not None:  # __stack_pointer
            high = max(high or 0, v)
    return high


def _data_high(b: bytes, p: int, high: int | None) -> int | None:
    n, p = _uleb(b, p)
    for _ in range(n):
        flags, p = _uleb(b, p)
        if flags & 1:  # passive: not placed in memory
            size, p = _uleb(b, p)
        else:
            if flags & 2:
                _, p = _uleb(b, p)
            off, p = _init_expr(b, p)
            size, p = _uleb(b, p)
            high = max(high or 0, (off or 0) + size)
        p += size
    return high


def high_water(b: bytes) -> int | None:
    """docs/wasm_hiwater.js cartHighWater: max(mutable i32 global init, end of active data)."""
    high = None
    for sid, p in _sections(b):
        if sid == 6:
            high = _globals_high(b, p, high)
        elif sid == 11:
            high = _data_high(b, p, high)
    return high


def _limits(b: bytes, p: int) -> tuple[int, int | None, int]:
    flags, p = _uleb(b, p)
    lo, p = _uleb(b, p)
    hi = None
    if flags & 1:
        hi, p = _uleb(b, p)
    if flags & 8:  # custom page size
        _, p = _uleb(b, p)
    return lo, hi, p


def _name(b: bytes, p: int) -> tuple[str, int]:
    n, p = _uleb(b, p)
    return b[p : p + n].decode(), p + n


def _skip_import_desc(b: bytes, kind: int, p: int) -> int:
    if kind == 0:  # func: type index
        return _uleb(b, p)[1]
    if kind == 1:  # table: reftype + limits
        return _limits(b, p + 1)[2]
    if kind == 3:  # global: valtype + mutability
        return p + 2
    return _uleb(b, p + 1)[1]  # tag: attribute + type index


def memory_import(b: bytes) -> tuple[int, int | None] | None:
    """(min, max) pages of the imported env.memory, or None if the module imports none."""
    for sid, p in _sections(b):
        if sid != 2:
            continue
        n, p = _uleb(b, p)
        for _ in range(n):
            mod, p = _name(b, p)
            field, p = _name(b, p)
            kind = b[p]
            if kind == 2:
                lo, hi, p = _limits(b, p + 1)
                if (mod, field) == ("env", "memory"):
                    return lo, hi
            else:
                p = _skip_import_desc(b, kind, p + 1)
    return None
