"""SNYD 90 loader depackers, transcribed from the decrypted loader (in place, like the 68000).

bytekiller ($7D8): stream read backwards from the end: -(a0) = unpacked length,
-(a0) = checksum, -(a0) = first bit long; bits LSB first with a sentinel.
wordruns ($8C8): a word-RLE expansion pass applied to bytekiller's output.
"""
import struct


class _Bits:
    def __init__(self, mem: bytearray, a0: int) -> None:
        self.mem, self.a0 = mem, a0
        self.d5 = 0
        self.d0 = self.pop()

    def pop(self) -> int:
        self.a0 -= 4
        v = struct.unpack('>I', self.mem[self.a0:self.a0 + 4])[0]
        self.d5 ^= v
        return v

    def bit(self) -> int:
        c = self.d0 & 1
        self.d0 >>= 1
        if self.d0 == 0:  # sentinel shifted out: refill, X=1 enters at the top
            self.d0 = self.pop()
            c = self.d0 & 1
            self.d0 = (self.d0 >> 1) | 0x80000000
        return c

    def bits(self, n: int) -> int:
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bit()
        return v


def bytekiller(packed: bytes) -> bytes:
    a0 = len(packed)
    size = struct.unpack('>I', packed[a0 - 4:a0])[0]
    mem = bytearray(max(size, a0))
    mem[:a0] = packed
    b = _Bits(mem, a0 - 4)  # first pop = checksum: re-pop the bit long below it
    b.d0 = b.pop()
    a2 = size
    while a2 > 0:
        if not b.bit():
            if not b.bit():
                n = b.bits(3)             # 1..8 literals
                a2 = _lit(b, mem, a2, n)
                continue
            off, cnt = b.bits(8), 1       # 2-byte copy, 8-bit offset
        else:
            k = b.bits(2)
            if k == 3:
                a2 = _lit(b, mem, a2, b.bits(8) + 8)
                continue
            if k == 2:
                cnt = b.bits(8)
                off = b.bits(12)
            else:
                cnt = k + 2
                off = b.bits(9 + k)
        for _ in range(cnt + 1):
            a2 -= 1
            mem[a2] = mem[a2 + off]
    assert b.d5 == 0, f'bytekiller checksum {b.d5:08x}'
    return bytes(mem[:size])


def _lit(b: _Bits, mem: bytearray, a2: int, d3: int) -> int:
    for _ in range(d3 + 1):
        a2 -= 1
        mem[a2] = b.bits(8)
    return a2


def wordruns(data: bytes) -> bytes:
    def rd(fmt: str, a: int) -> tuple[int, int]:
        n = struct.calcsize(fmt)
        return struct.unpack(fmt, mem[a - n:a])[0], a - n

    mem = bytearray(data)
    a1 = len(data)
    end, a1 = rd('>I', a1)
    if end > len(mem):
        mem += bytes(end - len(mem))
    a6 = end
    d1, a1 = rd('>I', a1)
    flag, a1 = rd('>H', a1)
    if flag:
        a2, a1 = rd('>I', a1)
        while a6 != a2:
            a1, a6 = a1 - 2, a6 - 2
            mem[a6:a6 + 2] = mem[a1:a1 + 2]
    for _ in range(d1 & 0xFFFF):
        fill, a1 = rd('>H', a1)
        a3, a1 = rd('>I', a1)
        a2, a1 = rd('>I', a1)
        while a6 != a3:
            a1, a6 = a1 - 2, a6 - 2
            mem[a6:a6 + 2] = mem[a1:a1 + 2]
        while a6 != a2:
            a6 -= 2
            mem[a6:a6 + 2] = struct.pack('>H', fill)
        if a6 == 0:
            break
    return bytes(mem[:end])
