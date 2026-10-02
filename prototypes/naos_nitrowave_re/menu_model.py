"""Model of the BATTLETEC menu (MENU.PRG), frame by frame, in ST RAM.

The VBL program runs through vbl68k (the original 68000 code); the main-loop
routines ($6c4, $630/$794/$7dc/$7b4, $76c) are transcribed below with their
addresses. menu_frames(n) yields (display_screen_address, mem) after each VBL.
"""
from vbl68k import CPU, menu_vbl_program

TD = open(__file__.rsplit('/', 1)[0] + '/menu_td.bin', 'rb').read()
PIC, PIC_LEN = 0xC418, 160 + 59800
SCR_A, SCR_B = 0x69100, 0x59A00
TEXT0, PATH0 = 0x1AE50, 0x1B956
PATH_PERIOD = 0x2CA
# font sheets, row 0: gfx A, gfx B (the other buffer), mask A, mask B; rows +0x14a0
FONT = (0x1C6C4, 0x2440E, 0x2C148, 0x33E92)
ROW_STEP = 0x14A0
# where $7dc appends a letter's three columns (table entries 23..25)
SLOT = (0x1C526, 0x1C59E, 0x1C616, 0x1C68E)
# BSS variables
V_TEXT, V_PATH, V_PCNT, V_PAUSE, V_PAUSE_N, V_SIX, V_TOGGLE = (
    0x3D8EA, 0x3D8E6, 0x3D904, 0x3D907, 0x3D902, 0x3D906, 0x3D908)
V_DRAW, V_BG, V_GFX, V_MASK = 0x3D8D6, 0x3D8E2, 0x3D8DA, 0x3D8DE


class Menu:
    def __init__(self):
        m = bytearray(0x80000)
        m[:len(TD)] = TD
        self.m = m
        self.cpu = CPU(m)
        self.prog = menu_vbl_program()
        for i in range(0xF01):  # $496/$4b6: mask word 0 copied over word 1
            for src in (0x2C150, 0x33E92):
                a = src + 8 * i
                m[a + 2:a + 6] = m[a:a + 4]
        for s in (SCR_A, SCR_B):  # $aa..$e6
            m[s + 160:s + PIC_LEN] = m[PIC + 160:PIC + PIC_LEN]
        self.l(V_TEXT, TEXT0)
        self.w(V_PCNT, 0)
        self.l(V_PATH, PATH0)
        m[V_PAUSE] = m[V_TOGGLE] = 0
        self.shown = SCR_A
        self.f6c4()
        self.f794()
        self.f76c()
        self.f630()

    def l(self, a, v):
        self.m[a:a + 4] = v.to_bytes(4, 'big')

    def w(self, a, v):
        self.m[a:a + 2] = v.to_bytes(2, 'big')

    def rl(self, a):
        return int.from_bytes(self.m[a:a + 4], 'big')

    def rw(self, a):
        return int.from_bytes(self.m[a:a + 2], 'big')

    def f6c4(self):
        m = self.m
        if m[V_TOGGLE] == 1:
            self.shown = SCR_A
            m[V_TOGGLE] = 0
            self.l(V_DRAW, SCR_B)
            self.l(V_BG, PIC)
            if m[V_PAUSE] != 1:
                self.l(V_MASK, 0x1C5BA)
                self.l(V_GFX, 0x1C4CA)
                return
        else:
            m[V_TOGGLE] = 1
            self.shown = SCR_B
            self.l(V_DRAW, SCR_A)
            self.l(V_BG, PIC)
        self.l(V_MASK, 0x1C632)
        self.l(V_GFX, 0x1C542)

    def f630(self):
        if self.m[V_PAUSE] == 1:
            self.f7b4()
            return
        for t in (self.rl(V_GFX), self.rl(V_MASK)):
            self.m[t:t + 104] = self.m[t + 4:t + 108]
        self.f794()

    def f794(self):
        self.m[V_SIX] += 1
        if self.m[V_SIX] == 6:
            self.m[V_SIX] = 0
            self.f7dc()

    def f7b4(self):
        n = self.rw(V_PAUSE_N) + 1
        self.w(V_PAUSE_N, n)
        if n == 0xA0:
            self.m[V_PAUSE] = 0
            self.w(V_PAUSE_N, 0)

    def f7dc(self):
        if self.m[V_PAUSE] == 1:
            self.f7b4()
            return
        p = self.rl(V_TEXT)
        c = self.m[p]
        self.l(V_TEXT, p + 1)
        if c == 0xFF:
            self.l(V_TEXT, TEXT0)
        elif c == 0x73:
            self.m[V_PAUSE] = 1
            self.w(V_PAUSE_N, 0)
        elif c != 0x20:
            self.append(c)

    def append(self, c):
        if c > 0x58:
            row, k = 4, c - 0x59
        elif c > 0x52:
            row, k = 3, c - 0x53
        elif c > 0x4C:
            row, k = 2, c - 0x4D
        elif c > 0x46:
            row, k = 1, c - 0x47
        else:
            row, k = 0, c - 0x41
        for base, slot in zip(FONT, SLOT):
            src = (base + row * ROW_STEP + ((k & 0xFF) * 0x18)) & 0xFFFFFF
            for j in range(3):
                self.l(slot + 4 * j, src + 8 * j)

    def f76c(self):
        n = self.rw(V_PCNT) + 1
        self.w(V_PCNT, n)
        if n == PATH_PERIOD:
            self.w(V_PCNT, 0)
            self.l(V_PATH, PATH0)

    def frame(self):
        """One main-loop iteration; returns the screen DISPLAYED in that frame."""
        shown = self.shown
        self.cpu.run(self.prog)
        self.f6c4()
        self.f630()
        self.f76c()
        return shown


def menu_frames(n, variant=0):
    """variant 1: a VBL fires between 'VBL = $78800' ($4e6) and the loop."""
    mm = Menu()
    if variant == 1:
        mm.cpu.run(mm.prog)
    if variant >= 10:  # experiment: force the six-frame letter counter's phase
        mm.m[V_SIX] = variant - 10
    for _ in range(n):
        yield mm.frame(), mm.m
