"""Model of F3, SAPRISTI 3615 GEN 4 (DAMIER3D.BIN at $400): from the RAM the
part's own set-up leaves at its main loop's first stop (Hatari dump e3.1500 +
registers), the main loop's four phases and the VBL program's six sections
(dam_fold.txt), checked against the Musashi oracle: dam_model.py N."""
import struct
import sys

LINE = 230
SNAP = 'dumps/e3.1500'
# main-loop phase k: (screen the next VBL draws, screen shown, a5, $3102C)
PHASES = [(0x4DF00, 0x5CA00, 0x53DF6, 0x56668), (0x3F400, 0x4DF00, 0x452F6, 0x47B68),
          (0x6B500, 0x3F400, 0x713F6, 0x73C68), (0x5CA00, 0x6B500, 0x628F6, 0x65168)]
FREEZE = 0x36204


class Part:
    def __init__(self):
        self.m = bytearray(open(__file__.rsplit('/', 1)[0] + '/' + SNAP, 'rb').read())
        regs = [int(x, 16) for x in open(__file__.rsplit('/', 1)[0] + '/' + SNAP + '.regs').read().split(',')]
        self.a2, self.a4, self.a5, self.a6 = regs[10], regs[12], regs[13], regs[14]
        self.phase = 0
        self.shown = 0x6B500  # $428

    # ---- memory
    def l(self, a):
        return int.from_bytes(self.m[a:a + 4], 'big')

    def w(self, a):
        return int.from_bytes(self.m[a:a + 2], 'big')

    def sl(self, a, v):
        self.m[a:a + 4] = (v & 0xFFFFFFFF).to_bytes(4, 'big')

    def sw(self, a, v):
        self.m[a:a + 2] = (v & 0xFFFF).to_bytes(2, 'big')

    def cp(self, d, s, n):
        self.m[d:d + n] = self.m[s:s + n]

    # ---- the VBL program
    def logo_line(self, dst, src):
        """11 groups: planes 1..3 (6 bytes, plane 0 left alone); the first
        and last cleared, the nine between from the logo's line."""
        self.m[dst + 2:dst + 8] = bytes(6)
        for g in range(1, 10):
            self.cp(dst + 8 * g + 2, src + 6 * (g - 1), 6)
        self.m[dst + 80 + 2:dst + 80 + 8] = bytes(6)

    def routine(self, addr):
        """One of the straight-line band routines: move.l (a6)[+],d16(a5),
        lea d16(a6),a6, lea d16(a5),a5, nop, rts."""
        pc = addr
        while True:
            op = self.w(pc)
            if op == 0x4E75:
                return
            if op == 0x4E71:
                pc += 2
            elif op in (0x2B5E, 0x2B56):
                d = struct.unpack('>h', self.m[pc + 2:pc + 4])[0]
                self.sl(self.a5 + d, self.l(self.a6))
                if op == 0x2B5E:
                    self.a6 += 4
                pc += 4
            elif op == 0x4DEE:
                self.a6 += struct.unpack('>h', self.m[pc + 2:pc + 4])[0]
                pc += 4
            elif op == 0x4BED:
                self.a5 += struct.unpack('>h', self.m[pc + 2:pc + 4])[0]
                pc += 4
            else:
                raise ValueError(f'routine ${addr:X}: op {op:04X} at ${pc:X}')

    def band(self, pair, lines):
        for _ in range(lines):
            self.routine(self.l(pair))
            self.routine(self.l(pair + 4))

    def vbl(self):
        scr = self.l(0x361F4)
        a4, a5 = self.a4, 0
        for i in range(36):
            self.logo_line(self.l(a4) + scr + LINE * i, self.l(a4 + 4) + a5)
            a4 += 8
            a5 += 54
        self.sl(0x361F8, a4)
        self.sl(0x361FC, a5)
        self.sl(0x36200, scr + LINE * 36)
        self.band(0x30F6C, 40)
        self.band(0x30F6C, 22)
        self.a6, self.a5 = self.l(0x31028), self.l(0x3102C)
        self.band(0x30FE8, 10)
        self.band(0x30FE8, 16)
        self.band(0x30FE8, 2)
        d7, d6, a4 = self.l(0x36200), self.l(0x361FC), self.l(0x361F8)
        for i in range(16):
            self.logo_line(self.l(a4) + d7, self.l(a4 + 4) + d6)
            a4 += 8
            d7 += LINE
            d6 += 54
        self.scroller()

    def scroller(self):
        a4 = self.l(0x30C92)
        for c in range(9):
            src = self.l(0x30C6E + 4 * c)
            for r in range(16):
                for g in range(3):
                    self.cp(a4 + LINE * r + 8 * g, src, 6)
                    src += 6
            a4 += 0x18
        a4 = self.l(0x30C9C)
        for k in range(104):
            self.m[a4 + 8 * k:a4 + 8 * k + 6] = bytes(6)
