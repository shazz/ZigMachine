"""Model of F1, MULTISPRITES (DEMO_RIC.BIN at $800): its VBL ($F96)
transcribed, from the RAM at its main loop's entry (dump r1.1500: the set-up
done, the title picture shown meanwhile). Checked against the oracle:
    ric_model.py N   (RAM after N VBLs vs ric_oracle.sh)"""
import struct
import subprocess
import sys

SNAP = 'dumps/r1.1500'
LIMIT = 0x2580  # sprite offsets below: the 3 masked groups skip plane 0
END = 0xFFFF


class Part:
    def __init__(self):
        self.m = bytearray(open(__file__.rsplit('/', 1)[0] + '/' + SNAP, 'rb').read()[:0x80000])
        self.shown = None  # the screen base the shifter shows (set once $316A runs out)

    def l(self, a):
        return int.from_bytes(self.m[a:a + 4], 'big')

    def w(self, a):
        return int.from_bytes(self.m[a:a + 2], 'big')

    def ws(self, a):
        return struct.unpack('>h', self.m[a:a + 2])[0]

    def sl(self, a, v):
        self.m[a:a + 4] = (v & 0xFFFFFFFF).to_bytes(4, 'big')

    def sw(self, a, v):
        self.m[a:a + 2] = (v & 0xFFFF).to_bytes(2, 'big')

    def vbl(self):
        """$F96 (the frozen VBL $EF4 is not modelled: no key)."""
        self.sl(0x7829E, 0x47524)  # Timer B: the line table and its count
        self.sw(0x7829C, 0xC6)
        self.screens()
        self.sprite_new()
        self.sprite_restore()
        self.sprite_third()
        self.scroller()
        self.scroll_colours()
        self.bars()

    def screens(self):
        """$FD8: the next of the four screens; the shifter follows once $316A
        has counted down."""
        a0 = self.l(0x4796A)
        if self.l(a0) == 0xFFFFFFFF:
            a0 = 0x47942
        n = (self.w(0x316A) - 1) & 0xFFFF
        self.sw(0x316A, n)
        if n & 0x8000:
            self.sw(0x316A, 0)
            self.shown = self.l(a0) & 0xFFFF00
        self.sl(0x47936, self.l(a0))
        self.sl(0x4796A, a0 + 4)

    def next_entry(self, var):
        a0 = self.l(var)
        if self.w(a0) == END:
            a0 = self.l(0x782D2)
        return a0

    def sprite_new(self):
        """$107C: one new sprite (masked, planes 1..3 -- all four at and above
        $2580) at the next path entry."""
        a0 = self.next_entry(0x47920)
        a4, a5, a6 = self.ws(a0), self.ws(a0 + 2), self.ws(a0 + 4)
        self.sl(0x47920, a0 + 6)
        scr = self.l(0x47936)
        dst, gfx, mask = (a4 + scr) & 0xFFFFFFFF, (a5 + self.l(0x47914)) & 0xFFFFFFFF, (a6 + self.l(0x47918)) & 0xFFFFFFFF
        for y in range(30):
            d, k = dst + 160 * y, mask + 160 * y
            if a4 < LIMIT:
                for g in range(3):
                    self.sl(d + 8 * g + 2, self.l(d + 8 * g + 2) & self.l(k + 8 * g + 2))
                    self.sw(d + 8 * g + 6, self.w(d + 8 * g + 6) & self.w(k + 8 * g + 6))
            else:
                for j in range(6):
                    self.sl(d + 4 * j, self.l(d + 4 * j) & self.l(k + 4 * j))
        for y in range(30):
            d, s = dst + 160 * y, gfx + 0x78 * y
            for g in range(3):
                self.sl(d + 8 * g + 2, self.l(d + 8 * g + 2) | self.l(s + 6 * g))
                self.sw(d + 8 * g + 6, self.w(d + 8 * g + 6) | self.w(s + 6 * g + 4))

    def sprite_restore(self):
        """$116E: the background back under an old sprite."""
        a0 = self.next_entry(0x47928)
        a1 = self.ws(a0)
        scr, bg = self.l(0x47936), self.l(0x4791C)
        for y in range(30):
            d, s = (a1 + scr + 160 * y) & 0xFFFFFF, (a1 + bg + 160 * y) & 0xFFFFFF
            if a1 < LIMIT:
                for g in range(3):
                    self.m[d + 8 * g + 2:d + 8 * g + 8] = self.m[s + 8 * g + 2:s + 8 * g + 8]
            else:
                self.m[d:d + 24] = self.m[s:s + 24]
        self.sl(0x47928, a0 + 6)

    def sprite_third(self):
        """$11F6: a third entry list: a mask (only at and above $2580) and nine
        words a line from the stream at $782DA (planes 1..3)."""
        a0, a1 = self.l(0x782DA), self.l(0x47924)
        a2 = self.ws(a1)
        a5 = (self.ws(a1 + 4) + self.l(0x47918)) & 0xFFFFFFFF
        a1 += 6
        scr = self.l(0x47936)
        if a2 >= LIMIT:
            for y in range(30):
                d, k = a2 + scr + 160 * y, a5 + 160 * y
                for j in range(6):
                    self.sl(d + 4 * j, self.l(d + 4 * j) & self.l(k + 4 * j))
        for y in range(30):
            d = (a2 + scr + 160 * y) & 0xFFFFFF
            for g in range(3):
                self.m[d + 8 * g + 2:d + 8 * g + 8] = self.m[a0:a0 + 6]
                a0 += 6
        if self.l(a0) == 0xBC614E:
            a0 = 0xCBD4
        self.sl(0x782DA, a0)
        if self.w(a1) == END:
            a1 = self.l(0x782D2)
        self.sl(0x47924, a1)

    def scroller(self):
        """$129E: the 1-plane scroller, 59 lines of plane 0 moved a word left
        and the next font column in. Each screen keeps its own text place
        (triples at $316C: font base var, text var, column counter)."""
        a0 = self.l(0x78270)
        a1, a2, a6 = self.l(a0), self.l(a0 + 4), self.l(a0 + 8)
        a0 += 12
        a5 = self.l(a2)
        if self.l(a0) == 0:
            a0 = 0x316C
        self.sl(0x78270, a0)
        d6 = self.m[a6]
        if d6 == 0:
            a5 += 1
            if self.m[a5] == 0:
                a5 = 0x449A
            self.sl(a2, a5)
            d6 = {0x49: 2, 0x69: 3, 0x6A: 2, 0x68: 3}.get(self.m[a5], 4)
        d1 = d6
        self.m[a6] = (d6 - 1) & 0xFF
        c = self.m[a5]
        if c == 0x67:
            c = 0x60
        c = (((c - 0x41) & 0xFF) << 1) & 0xFF
        a3 = (self.ws(0x4446 + c) + self.l(a1) - ((d1 << 1) & 0xFF)) & 0xFFFFFFFF
        scr = self.l(0x47936)
        for y in range(59):
            row = scr + 160 * y
            for k in range(19):
                self.m[row + 8 * k:row + 8 * k + 2] = self.m[row + 8 * k + 8:row + 8 * k + 10]
            self.m[row + 0x98:row + 0x9A] = self.m[a3 + 8 * y:a3 + 8 * y + 2]

    def scroll_colours(self):
        """$13CC: colour 1 of lines 0..58 (the scroller's rainbow) from the
        next table of the list at $4790E ($31A0 on, ended by -1)."""
        a0 = self.l(0x4790E)
        a1 = self.l(a0)
        a0 += 4
        if self.l(a0) == 0xFFFFFFFF:
            a0 = 0x31A0
        self.sl(0x4790E, a0)
        for y in range(59):
            self.m[0x47526 + 4 * y:0x47528 + 4 * y] = self.m[a1 + 6 + 2 * y:a1 + 8 + 2 * y]

    def bars(self):
        """$1400: colour 0 of lines 0..10 (+20, 40, 60, 80, 99) from the next
        table of the list at $4442 ($35A8 on, ended by 0)."""
        a0 = self.l(0x4442)
        a5 = self.l(a0)
        a0 += 4
        if self.l(a0) == 0:
            a0 = 0x35A8
        self.sl(0x4442, a0)
        for k in range(11):
            v = self.m[a5 + 2 * k:a5 + 2 * k + 2]
            for first in (0, 20, 40, 60, 80, 99):
                at = 0x47524 + 4 * (first + k)
                self.m[at:at + 2] = v


if __name__ == '__main__':
    N = int(sys.argv[1])
    subprocess.run(['./ric_oracle.sh', SNAP, str(N), '/dev/shm/nw_ric_o.bin'], check=True)
    p = Part()
    for _ in range(N):
        p.vbl()
    ref = open('/dev/shm/nw_ric_o.bin', 'rb').read()
    bad = [i for i in list(range(0x2400, 0x78300)) + list(range(0x78500, 0x7F000)) if p.m[i] != ref[i]]  # not the stacks
    print(N, 'VBLs:', len(bad), 'bytes differ', [hex(i) for i in bad[:12]])
