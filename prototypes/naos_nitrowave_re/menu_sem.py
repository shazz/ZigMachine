"""The menu's VBL program as plain loops (what the Zig port implements), checked
against the 68000 interpreter (vbl68k) over N frames:  menu_sem.py N

  erase: path word e; 32 rows of 224 bytes, screen+e+230r <- picture+e+230r
  draw:  path word d; a5 = screen+d+16; columns c=0..21 from tables gfx[c],
         mask[c]; row r=0..30 at a5+8c+230r:
           planes 0..3 &= mask word (both longs of the group, see init)
           planes 0,1 |= gfx long; plane 2 |= gfx plane-2 word, or on rows 4
           and 5 the gfx PLANE-3 word (move.l $284(a4),d2 / or.w d2).
"""
import sys

from menu_model import (V_BG, V_DRAW, V_GFX, V_MASK, V_PATH, Menu)

ERASE_ROWS, ERASE_BYTES, LINE = 32, 224, 230
COLS, ROWS, SRC_LINE = 22, 31, 160
PLANE3_ROWS = (4, 5)


def L(m, a):
    return int.from_bytes(m[a:a + 4], 'big')


def vbl_sem(mm):
    m = mm.m
    path = mm.rl(V_PATH)
    e, d = mm.rw(path), mm.rw(path + 2)
    mm.l(V_PATH, path + 4)
    scr, bg = mm.rl(V_DRAW), mm.rl(V_BG)
    for r in range(ERASE_ROWS):
        o = e + LINE * r
        m[scr + o:scr + o + ERASE_BYTES] = m[bg + o:bg + o + ERASE_BYTES]
    gt, mt = mm.rl(V_GFX), mm.rl(V_MASK)
    a5 = scr + d + 16
    for c in range(COLS):
        g, k = L(m, gt + 4 * c), L(m, mt + 4 * c)
        for r in range(ROWS):
            dst = a5 + 8 * c + LINE * r
            mask = L(m, k + SRC_LINE * r)
            for p in (0, 4):
                m[dst + p:dst + p + 4] = (L(m, dst + p) & mask).to_bytes(4, 'big')
            src = g + SRC_LINE * r
            m[dst:dst + 4] = (L(m, dst) | L(m, src)).to_bytes(4, 'big')
            w2 = m[src + 6:src + 8] if r in PLANE3_ROWS else m[src + 4:src + 6]
            m[dst + 4] |= w2[0]
            m[dst + 5] |= w2[1]


if __name__ == '__main__':
    a, b = Menu(), Menu()
    for k in range(int(sys.argv[1])):
        a.cpu.run(a.prog)
        vbl_sem(b)
        assert a.m == b.m, f'diverged at frame {k}'
        for mm in (a, b):
            mm.f6c4()
            mm.f630()
            mm.f76c()
    print('identical RAM for', sys.argv[1], 'frames')
