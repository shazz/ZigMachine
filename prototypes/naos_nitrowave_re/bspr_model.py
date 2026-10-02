"""Model of F2, BIGSPRITE + OVERSCAN (B_SPRITE.BIN at $800), from the file:
the init's precalculation, then the main loop + VBL program read back from the
code (bspr_prog.dis, NOTES.md "F2"). Checked against Hatari dumps (h2.*) and
the Musashi oracle: bspr_model.py N DUMP -> RAM after N main-loop passes vs DUMP.
"""
import struct
import sys

LINE = 230
SCR_A, SCR_B, BG = 0x5C200, 0x6AD00, 0x4D700
TAB_A, TAB_B = 0x1263E, 0x1277E  # erase tables, 80 longs each
V_SCREEN, V_TABLE = 0x12636, 0x1263A
V_PATH, V_GLOB, V_GN, V_GSTATE, V_PN, V_PSTATE = 0x12A56, 0x12A5A, 0x12A5E, 0x12A60, 0x12A62, 0x12A64
GFX0, MASK0 = 0x10FB6, 0x2CD22
SHIFT0 = 0x17BA2  # 15 more preshifts, 0x1680 apart
SPRITE_BYTES, MASK_BYTES = 0x1680, 0xB40
LINES, GROUPS = 80, 9
# $1218's states 2..7: (end, restart, next counter); state 1 waits
PATH_STATES = {2: (0x135B2, 0x12E32, 8), 3: (0x13D32, 0x13972, 4), 4: (0x14F86, 0x1416A, 1),
               5: (0x1697E, 0x1545A, 4), 6: (0x173CE, 0x1697E, None)}


class Part:
    def __init__(self):
        m = bytearray(0x80000)
        d = open(__file__.rsplit('/', 1)[0] + '/disk/B_SPRITE.BIN', 'rb').read()
        m[0x800:0x800 + len(d)] = d
        self.m = m
        self.init_bg()
        self.init_sprites()
        self.a6 = 0x12E32  # $1134
        self.freeze = 0
        self.half = 0  # 0: the loop's first stop ($1140), 1: its second ($11BA)
        self.shown = SCR_A

    def l(self, a):
        return int.from_bytes(self.m[a:a + 4], 'big')

    def sl(self, a, v):
        self.m[a:a + 4] = (v & 0xFFFFFFFF).to_bytes(4, 'big')

    def w(self, a):
        return int.from_bytes(self.m[a:a + 2], 'big')

    def sw(self, a, v):
        self.m[a:a + 2] = (v & 0xFFFF).to_bytes(2, 'big')

    def init_bg(self):
        """$86C..$8E2: a 32x64 tile ($107B6) seven times a line, four times
        down, from screen B's line 1; copied to screen A and the picture $4D700."""
        m, dst = self.m, 0x6AE86
        for r in range(64):
            row = m[0x107B6 + 32 * r:0x107B6 + 32 * r + 32]
            for k in range(7):
                o = dst + LINE * r + 32 * k
                m[o:o + 32] = row
        for k in range(1, 4):
            m[dst + 0x3980 * k:dst + 0x3980 * (k + 1)] = m[dst:dst + 0x3980]
        n = 2 * 0x7300
        m[0x5C386:0x5C386 + n] = m[dst:dst + n]
        m[0x4D886:0x4D886 + n] = m[dst:dst + n]

    def init_sprites(self):
        """$8E6..$D20: 15 preshifts of the 144x80 sprite (each the last moved
        right one pixel, $1E36), and 16 masks: per group, NOT(OR of the 4 planes)
        twice. The sixteenth preshift's sources are listed in mask order."""
        m = self.m
        srcs = [GFX0] + [SHIFT0 + SPRITE_BYTES * k for k in range(15)]
        prev = GFX0
        for dst in srcs[1:]:
            m[dst:dst + SPRITE_BYTES] = m[prev:prev + SPRITE_BYTES]
            self.shift(dst)
            prev = dst
        for k, src in enumerate(srcs):
            dst = MASK0 + MASK_BYTES * k
            for g in range(0x2D0):
                v = 0
                for p in range(4):
                    v |= self.w(src + 8 * g + 2 * p)
                v ^= 0xFFFF
                self.sw(dst + 4 * g, v)
                self.sw(dst + 4 * g + 2, v)

    def shift(self, a0):
        """$1E36: each plane of each line, 9 words, one pixel right."""
        for line in range(LINES):
            for p in range(4):
                x = 0
                for g in range(GROUPS):
                    a = a0 + 72 * line + 2 * p + 8 * g
                    v = self.w(a)
                    self.sw(a, (v >> 1) | (x << 15))
                    x = v & 1

    def vbl(self):
        m, scr, tab = self.m, self.l(V_SCREEN), self.l(V_TABLE)
        for i in range(LINES):
            off = self.l(tab + 4 * i) + LINE * i
            m[scr + off:scr + off + 72] = m[BG + off:BG + off + 72]
        glob = self.l(self.l(V_GLOB))
        a6 = self.a6
        for i in range(LINES):
            pos = (self.l(a6) + glob) & 0xFFFFFFFF
            self.sl(tab + 4 * i, pos)
            dst = (pos + scr + LINE * i) & 0xFFFFFF
            g = self.l(a6 + 4) + 72 * i
            k = self.l(a6 + 8) + 36 * i
            a6 += 12
            for j in range(GROUPS):
                mk = self.l(k + 4 * j)
                for h in (0, 4):
                    a = dst + 8 * j + h
                    self.sl(a, (self.l(a) & mk) | self.l(g + 8 * j + h))

    def path(self):
        """$1218: a6 for the next VBL."""
        if self.freeze:
            self.a6 = self.l(V_PATH)
            return
        st = self.w(V_PSTATE)
        if st == 1:
            n = self.w(V_PN) - 1
            self.sw(V_PN, n)
            if n:
                self.a6 = self.l(V_PATH)
                return
            self.sw(V_PSTATE, 2)
            self.sw(V_PN, 8)
        self.a6 = self.path_step()

    def path_step(self):
        while True:
            st = self.w(V_PSTATE)
            a0 = self.l(V_PATH) + 12
            if st in PATH_STATES:
                end, restart, nxt = PATH_STATES[st]
                if a0 == end:
                    n = self.w(V_PN) - 1
                    self.sw(V_PN, n)
                    if n == 0:
                        if nxt is None:
                            self.sw(V_PSTATE, 7)
                            continue
                        self.sw(V_PSTATE, st + 1)
                        self.sw(V_PN, nxt)
                        continue
                    a0 = restart
                self.sl(V_PATH, a0)
                return a0
            self.sw(V_PSTATE, 7)  # $13CC
            if a0 == 0x1779A:  # $11FE: start over, then $1218 again
                self.sw(V_PSTATE, 1)
                self.sw(V_PN, 0x190)
                self.sl(V_PATH, 0x12A66)
                self.path()
                return self.a6
            self.sl(V_PATH, a0)
            return a0

    def glob_step(self):
        """$140C: the offset the whole sprite moves by."""
        if self.freeze:
            return
        if self.w(V_GSTATE) == 1:
            n = self.w(V_GN) - 1
            self.sw(V_GN, n)
            if n:
                return
            self.sw(V_GSTATE, 2)
            self.sw(V_GN, 0xA)
        a0 = self.l(V_GLOB) + 4
        self.sl(V_GLOB, a0)
        if a0 != 0x12A52:
            return
        n = self.w(V_GN) - 1
        self.sw(V_GN, n)
        if n == 0:
            self.sw(V_GN, 0x320)
            self.sw(V_GSTATE, 1)
            self.sl(V_GLOB, 0x128C2)
            self.glob_step()
            return
        self.sl(V_GLOB, 0x128C2)

    def frame(self):
        """VBL, then the main loop's work up to its next stop. -> screen shown
        while that VBL ran."""
        shown = self.shown
        self.vbl()
        self.path()
        self.glob_step()
        if self.half == 0:
            self.sl(V_SCREEN, SCR_A)
            self.sl(V_TABLE, TAB_B)
            self.shown = SCR_B
        else:
            self.sl(V_SCREEN, SCR_B)
            self.sl(V_TABLE, TAB_A)
            self.shown = SCR_A
        self.half ^= 1
        return shown


if __name__ == '__main__':
    p = Part()
    p.shown = SCR_A
    for _ in range(int(sys.argv[1])):
        p.frame()
    ref = open(sys.argv[2], 'rb').read()
    for name, lo, hi in (('code+data', 0x800, 0x17B66), ('preshifts+masks', 0x17B66, 0x40000),
                         ('bg', BG, BG + 0xE900), ('screen A', SCR_A, SCR_A + 0xE900), ('screen B', SCR_B, SCR_B + 0xE900)):
        d = [hex(i) for i in range(lo, hi) if p.m[i] != ref[i]]
        print(f'{name}: {len(d)} bytes differ {d[:8]}')

CAPDIR = "p2"
PALETTE = 0x10796
ROWS = (2, 256)  # capture rows lit: screen lines 1..254 (fit_part.py)
