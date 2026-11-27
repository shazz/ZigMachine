"""LOCAL ONLY: the two Mega Drive stream formats a Virtua Racing Deluxe (32X) panorama is stored in (vr32x_pan.py): Kosinski
(tiles) and Enigma (nametables), clean-room from the 68000 code's behaviour (the formats are in vr32x_pan's docstring).
Holds no data.
"""

from __future__ import annotations


class PackError(ValueError):
    pass


def _u16(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 2], "big")


def signed(v: int, bits: int) -> int:
    return v - (1 << bits) if v >> (bits - 1) else v


class _Kos:
    def __init__(self, src: bytes, at: int) -> None:
        self.src, self.p = src, at
        self.desc, self.left = self.byte() | self.byte() << 8, 16

    def byte(self) -> int:
        if self.p >= len(self.src):
            raise PackError("kosinski stream runs past the end")
        self.p += 1
        return self.src[self.p - 1]

    def bit(self) -> int:
        b, self.desc, self.left = self.desc & 1, self.desc >> 1, self.left - 1
        if self.left == 0:
            self.desc, self.left = self.byte() | self.byte() << 8, 16
        return b


def _kos_long(s: _Kos) -> tuple[int, int] | None:
    """The two/three-byte match: (offset, count), count 0 = a no-op; None = the end mark."""
    lo, hi = s.byte(), s.byte()
    off = ((hi & 0xF8) << 5 | lo) - 0x2000
    if hi & 7:
        return off, (hi & 7) + 2
    n = s.byte()
    return None if n == 0 else (off, 0 if n == 1 else n + 1)


def kosinski(src: bytes, at: int) -> bytes:
    s, out = _Kos(src, at), bytearray()
    while True:
        if s.bit():
            out.append(s.byte())
            continue
        if s.bit():
            got = _kos_long(s)
            if got is None:
                return bytes(out)
            off, count = got
        else:
            count = (s.bit() << 1 | s.bit()) + 2
            off = s.byte() - 256
        if -off > len(out):
            raise PackError(f"kosinski at {at:#x}: offset {off} before the start")
        for _ in range(count):
            out.append(out[off])


class _Bits:
    def __init__(self, src: bytes, at: int) -> None:
        self.src, self.p, self.n, self.acc = src, at, 0, 0

    def get(self, k: int) -> int:
        v = 0
        for _ in range(k):
            if self.n == 0:
                if self.p >= len(self.src):
                    raise PackError("enigma stream runs past the end")
                self.acc, self.p, self.n = self.src[self.p], self.p + 1, 8
            self.n -= 1
            v = v << 1 | (self.acc >> self.n) & 1
        return v


def _eni_inline(b: _Bits, flags: int, nbits: int, base: int) -> int:
    v = base
    for k, m in enumerate((0x8000, 0x4000, 0x2000, 0x1000, 0x0800)):
        if flags & (0x10 >> k) and b.get(1):
            v += m
    return (v + b.get(nbits)) & 0xFFFF


def enigma(src: bytes, at: int, base: int) -> list[int]:
    nbits, flags = src[at], src[at + 1]
    inc, com = (_u16(src, at + 2) + base) & 0xFFFF, (_u16(src, at + 4) + base) & 0xFFFF
    b, out = _Bits(src, at + 6), []
    while True:
        if b.get(1) == 0:
            t, n = b.get(1), b.get(4) + 1
            out += [com] * n if t else [(inc + i) & 0xFFFF for i in range(n)]
            inc = inc if t else (inc + n) & 0xFFFF
            continue
        t, n = b.get(2), b.get(4) + 1
        if t == 3 and n == 16:
            return out
        if t == 3:
            out += [_eni_inline(b, flags, nbits, base) for _ in range(n)]
            continue
        v, step = _eni_inline(b, flags, nbits, base), (0, 1, -1)[t]
        out += [(v + step * i) & 0xFFFF for i in range(n)]
