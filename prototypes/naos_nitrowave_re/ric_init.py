"""F1's set-up from its figure choice ($A3E) to the main loop ($D98),
transcribed, from the RAM just before the choice (dumps/f1_pre.bin, the same
for every run). ric_init.py checks it against Hatari's RAM at the main loop for
each forced figure (dumps/f1_F.bin, run_ric.sh F)."""
import struct

from ric_model import Part
import sys

# $A4A..$AAE: figure -> (path, the new-sprite list's distance, $316A countdown)
FIGURES = [(0x5096, 0x2A0, None), (0x5728, 0x270, None), (0x5DBA, 0x210, None), (0x6398, 0x300, 0x8C)]
ENTRY = 0x18  # one sprite step in a path: 4 entries of 6 bytes


class Init:
    def __init__(self, mem):
        self.m = mem

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

    def cp(self, d, s, n):
        self.m[d:d + n] = self.m[s:s + n]

    def run(self, figure):
        self.paths(figure)
        self.tables()
        self.screens()
        self.precalc()
        self.finish()

    def paths(self, f):
        path, gap, count = FIGURES[f]
        if count is not None:
            self.sw(0x316A, count)
        self.sl(0x782CE, gap)
        self.sl(0x782D2, path)
        self.sl(0x47928, path)
        self.sl(0x47924, path + ENTRY)
        self.sl(0x47920, path + ENTRY + gap)
        self.sl(0x782DA, 0xCBD4)
        for k in range(8):  # $AEA: eight sprites a step apart
            self.sl(0x782E2 + 4 * k, path + ENTRY * k)

    def tables(self):
        """$B1A..$BB0: the line colour table, the mirrored rows, the logo palette."""
        for i in range(0xF2):
            self.cp(0x47524 + 4 * i, 0x1B902 + 2 * i, 2)
            self.cp(0x47526 + 4 * i, 0x3022 + 2 * i, 2)
        self.sl(0x4790E, 0x31A0)
        for k in range(8):
            a0 = 0x2D56 + 0x3C * k
            for j in range(15):
                self.cp(a0 + 0x3C - 2 - 2 * j, a0 + 2 * j, 2)
        self.cp(0x2D56 + 0x1E0, 0x2D56, 120)
        self.cp(0x782AA, 0xCBD8 + 4, 32)
        self.sl(0x47914, 0x68C2 + 0x20)
        self.sl(0x47918, 0x9312 + 0x80)

    def screens(self):
        """$BB6..$C42: four screens $9B00 apart from the first 256-byte
        boundary after $4796E; the picture's lower part into the first, copied
        on into the second and third."""
        s = (0x4796E & ~0xFF) + 0x100
        self.sl(0x4793A, s)
        scr = [s + 0x9B00 * k for k in range(4)]
        for k in range(4):
            self.sl(0x47942 + 4 * k, scr[k])
        self.sl(0x47942 + 16, 0xFFFFFFFF)
        self.cp(scr[0] + 0x3840, 0xCBD8 + 0x80, 0xBB8 * 4)
        self.cp(scr[1], scr[0], 32000)
        self.cp(scr[2], scr[1], 32000)
        self.sl(0x9312, scr[2])
        self.sl(0x9316, scr[3])
        self.sl(0x47936, 0x64B6E)

    def draw(self, var):
        """$152C: the sprite at path entry *var (moving it on): mask all four
        planes, then the gfx into planes 1..3."""
        a0 = self.l(var)
        if self.w(a0) == 0xFFFF:
            a0 = self.l(0x782D2)
        a4, a5, a6 = self.ws(a0), self.ws(a0 + 2), self.ws(a0 + 4)
        self.sl(var, a0 + 6)
        dst = (a4 + self.l(0x47936)) & 0xFFFFFFFF
        gfx = (a5 + self.l(0x47914)) & 0xFFFFFFFF
        mask = (a6 + self.l(0x47918)) & 0xFFFFFFFF
        for y in range(30):
            d, k = dst + 160 * y, mask + 160 * y
            for j in range(6):
                self.sl(d + 4 * j, self.l(d + 4 * j) & self.l(k + 4 * j))
        for y in range(30):
            d, s = dst + 160 * y, gfx + 0x78 * y
            for g in range(3):
                self.sl(d + 8 * g + 2, self.l(d + 8 * g + 2) | self.l(s + 6 * g))
                self.sw(d + 8 * g + 6, self.w(d + 8 * g + 6) | self.w(s + 6 * g + 4))

    def precalc(self):
        """$C50: screen 2 into the work screen, the eight sprites drawn, and the
        first one's 30 lines of planes 1..3 kept at *$782DA -- until the first
        sprite's path ends."""
        while True:
            work = self.l(0x47936)
            self.cp(work, self.l(0x47942 + 4), 0x23F0 * 4)
            for k in range(8):
                var = 0x782E2 + 4 * k
                self.sl(0x782DE, self.l(var))
                self.draw(0x782DE)
                if k:
                    self.sl(var, self.l(0x782DE))
            a2 = self.l(0x782E2)
            self.sl(0x782E2, a2 + 6)
            a1 = self.l(0x782DA)
            self.sl(0x782DA, a1 + 0x21C)
            a0 = (self.ws(a2) + work) & 0xFFFFFFFF
            for y in range(30):
                for g in range(3):
                    self.cp(a1 + 6 * g, a0 + 8 * g + 2, 6)
                a1 += 0x12
                a0 += 160
            if self.w(self.l(0x782E2)) == 0xFFFF:
                return

    def finish(self):
        """$CB6..$D82."""
        self.sl(self.l(0x782DA), 0xBC614E)
        self.sl(0x782DA, 0xCBD4 + 0x870)
        self.sl(0x47936, self.l(0x4791C))
        self.cp(self.l(0x9316), self.l(0x9312), 0x2440 * 4)
        self.sl(0x4796A, 0x47942)
        self.cp(self.l(0x4791C), self.l(0x47942), 32000)
        for k, font in enumerate((0x346C4, 0x3925C, 0x3DDF4, 0x4298C)):
            self.sl(0x78274 + 8 * k, font)
            self.sl(0x78278 + 8 * k, 0x449A)
        self.sl(0x78270, 0x316C)
        self.sw(0x7826E, 0)


if __name__ == '__main__':
    pre = open('dumps/f1_pre.bin', 'rb').read()[:0x80000]
    for f in range(4):
        m = bytearray(pre)
        Init(m).run(f)
        ref = open(f'dumps/f1_{f}.bin', 'rb').read()
        # Hatari stops at $D98 a few VBLs into the loop: as many as $316A shows
        vbls = int.from_bytes(m[0x316A:0x316C], 'big') - int.from_bytes(ref[0x316A:0x316C], 'big')
        vbl = Part.__new__(Part)
        vbl.m, vbl.shown = m, None
        for _ in range(vbls):
            vbl.vbl()
        bad = [i for i in list(range(0x2400, 0x78300)) + list(range(0x78500, 0x7F000)) if m[i] != ref[i]]
        print('figure', f, len(bad), 'bytes differ', [hex(i) for i in bad[:10]])
