# Pack-Ice depacker in Python (a transcription of libs/zig/depackers/ice.zig) with diagnostics,
# to see why the 5th credit picture's stream (file offset 1,270,360) does not depack.
# usage: unice_dbg.py <file> <offset> [out.bin] [--pad]
#   --pad: a match reading past the output's end reads zeros (an image that starts black)
import struct
import sys

LIT_BITS = [1, 1, 2, 7, 0xE]
LIT_MAX = [3, 3, 7, 0xFF, 0x8000]
LEN_BITS = [9, 1, 0, 0xFF, 0xFF]
LEN_BASE = [8, 4, 2, 1, 0]
OFF_BITS = [0x0B, 0x04, 0x07]
OFF_BASE = [0x0120, 0x0000, 0x0020]


class Bad(Exception):
    pass


class S:
    def __init__(self, src):
        self.src, self.pos, self.buf = src, len(src), 0

    def byte(self):
        if self.pos == 0:
            raise Bad('ran out of packed bytes')
        self.pos -= 1
        return self.src[self.pos]

    def bit(self):
        out = (self.buf >> 7) & 1
        self.buf = (self.buf << 1) & 255
        if self.buf:
            return out
        b = self.byte()
        self.buf = ((b << 1) | out) & 255
        return b >> 7

    def bits(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bit()
        return v

    def prefix(self, width):
        d = width - 1
        while True:
            if self.bit() == 0:
                return d
            d -= 1
            if d < 0:
                return -1


def depack(src, pad):
    plen, olen = struct.unpack('>II', src[4:12])
    s = S(src[:plen])
    dst = bytearray(olen + (70000 if pad else 0))
    w = olen
    while w > 0:
        if s.bit():
            extra = 0
            if s.bit():
                total = 0
                for width, mx in zip(LIT_BITS, LIT_MAX):
                    v = s.bits(width + 1)
                    total = (total + v) & 0xFFFF
                    if v != mx:
                        break
                extra = total + 1
            for _ in range(extra + 1):
                if w == 0:
                    raise Bad('literal past the start')
                w -= 1
                dst[w] = s.byte()
        if w == 0:
            break
        p = s.prefix(4)
        col = p + 1
        length = LEN_BASE[col]
        if length:
            if LEN_BITS[col] != 0xFF:
                length = (length + s.bits(LEN_BITS[col] + 1)) & 0xFFFF
            c2 = s.prefix(2) + 1
            off = (s.bits(OFF_BITS[c2] + 1) + OFF_BASE[c2]) & 0xFFFF
            if off:
                off = (off + length) & 0xFFFF
        else:
            long = s.bit()
            off = (s.bits(9 if long else 6) + (0x40 if long else 0)) & 0xFFFF
        read = w + off + 1
        if read > len(dst):
            raise Bad('match reads past the end: w=%d off=%d (written %d of %d)' % (w, off, olen - w, olen))
        for _ in range(length + 2):
            if w == 0:
                raise Bad('match past the start')
            read -= 1
            w -= 1
            dst[w] = dst[read]
    return bytes(dst[:olen]), s.pos


d = open(sys.argv[1], 'rb').read()
off = int(sys.argv[2])
try:
    out, left = depack(d[off:], '--pad' in sys.argv)
    print('ok', len(out), 'packed bytes left', left)
    if len(sys.argv) > 3 and not sys.argv[3].startswith('--'):
        open(sys.argv[3], 'wb').write(out)
except Bad as e:
    print('FAIL', e)
