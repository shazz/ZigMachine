"""ZX0 container depacker, written from libs/zig/depackers/zx0.zig's format notes (NOT a port of its code): the
independent oracle the Bad Apple reference decoder reads the packed blocks with."""
from __future__ import annotations

MAGIC = b"ZX0!"
HEADER_LEN = 10  # container v1 with fx none (zx0pack's default): magic, version, fx, u32 length


class Zx0Error(ValueError):
    pass


class _Bits:
    def __init__(self, src: bytes, pos: int) -> None:
        self.src, self.pos, self.mask, self.bits, self.last, self.back = src, pos, 0, 0, 0, False

    def byte(self) -> int:
        if self.pos >= len(self.src):
            raise Zx0Error("stream overruns its input")
        self.last = self.src[self.pos]
        self.pos += 1
        return self.last

    def bit(self) -> int:
        if self.back:
            self.back = False
            return self.last & 1
        self.mask >>= 1
        if self.mask == 0:
            self.mask = 0x80
            self.bits = self.byte()
        return 1 if self.bits & self.mask else 0

    def gamma(self, inverted: bool) -> int:
        value = 1
        while self.bit() == 0:
            if value >= 1 << 26:
                raise Zx0Error("runaway gamma")
            value = (value << 1) | (self.bit() ^ int(inverted))
        return value


def depack(src: bytes) -> bytes:
    """Depack one ZX0! container (fx none). Raises Zx0Error on anything unreadable, never a partial result."""
    if len(src) < HEADER_LEN or src[:4] != MAGIC or src[4] != 1 or src[5] != 0:
        raise Zx0Error("not a plain ZX0! v1 container")
    total = int.from_bytes(src[6:10], "little")
    if total == 0:
        return b""
    r, out, last_off, phase = _Bits(src, HEADER_LEN), bytearray(), 1, "lit"
    while True:
        if phase == "lit":
            n = r.gamma(False)
            if n > total - len(out) or r.pos + n > len(src):
                raise Zx0Error("literal run overruns")
            out += src[r.pos:r.pos + n]
            r.pos += n
        else:
            if phase == "new":
                msb = r.gamma(True)
                if msb == 256:
                    break
                last_off = msb * 128 - (r.byte() >> 1)
                r.back = True
                n = r.gamma(False) + 1
            else:
                n = r.gamma(False)
            if last_off == 0 or last_off > len(out) or n > total - len(out):
                raise Zx0Error("bad match")
            for _ in range(n):
                out.append(out[-last_off])
        new = r.bit() == 1
        phase = "new" if new else ("rep" if phase == "lit" else "lit")
    if len(out) != total:
        raise Zx0Error("length mismatch")
    return bytes(out)
