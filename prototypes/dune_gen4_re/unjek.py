"""unjek.py IN.PRG OUT.PRG: depack a JEK Packer V1.3 GEMDOS program.

Transcribed from the depack stub at TEXT+$16C..$246 of DUNE.PRG (a ByteKiller-style
backward bitstream). The packed stream is read backwards from the END of TEXT and
the output is written backwards from TEXT+$300+len. The stream runs below
TEXT+$300, so the whole TEXT is the input, not TEXT[$300:].
The output is itself a GEMDOS PRG (its own $601A header + relocation table).
"""
import struct
import sys


class Bits:
    def __init__(self, src: bytes, end: int):
        self.src, self.p = src, end
        self.d5 = 0
        self.d0 = 0

    def pop(self) -> int:
        self.p -= 4
        v = struct.unpack('>I', self.src[self.p:self.p + 4])[0]
        self.d5 ^= v
        return v

    def bit(self) -> int:
        c = self.d0 & 1
        self.d0 >>= 1
        if self.d0:
            return c
        v = self.pop()                      # reload: roxr with X=1 marks the top bit
        c = v & 1
        self.d0 = (v >> 1) | 0x80000000
        return c

    def get(self, n: int) -> int:
        r = 0
        for _ in range(n):
            r = (r << 1) | self.bit()
        return r


def unjek(text: bytes) -> bytes:
    b = Bits(text, len(text))
    size = b.pop()
    b.d5 = b.pop()
    b.d0 = b.pop()
    out = bytearray(size)
    a2 = size

    def lit(n):
        nonlocal a2
        for _ in range(n + 1):
            a2 -= 1
            out[a2] = b.get(8)

    def copy(off, n):
        nonlocal a2
        for _ in range(n + 1):
            a2 -= 1
            out[a2] = out[a2 + off]

    while a2 > 0:
        if not b.bit():
            if b.bit():
                copy(b.get(8), 1)
            else:
                lit(b.get(3))
            continue
        k = b.get(2)
        if k < 2:
            copy(b.get(9 + k), k + 2)
        elif k == 3:
            lit(b.get(8) + 8)
        else:
            n = b.get(8)
            copy(b.get(12), n)
    assert b.d5 == 0, f'checksum residue {b.d5:#x}'
    return bytes(out)


if __name__ == '__main__':
    d = open(sys.argv[1], 'rb').read()
    assert d[:2] == b'\x60\x1a'
    tlen = struct.unpack('>I', d[2:6])[0]
    out = unjek(d[28:28 + tlen])
    open(sys.argv[2], 'wb').write(out)
    h = struct.unpack('>HIIIIIIH', out[:28])
    print(f'depacked {len(out)} bytes, header {h[0]:#x} text={h[1]:#x} data={h[2]:#x} bss={h[3]:#x}')
