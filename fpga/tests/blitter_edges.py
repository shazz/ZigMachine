"""The edge cases the blitter spec names, as a hand-written script (same format as
blitter_scripts.py): zero-size, fully clipped, negative coordinates, a line along the clip
edge, degenerate triangles, the region and window boundaries, DESC over an overlap."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from blitter_scripts import BLIT, CLIP, DESC, FILL, LINE, PLANE, TRI, Script, do, halftone, mm, regs


def fills(s: Script) -> None:
    base = regs(mt=mm.MT_B, con=0, con2=0, color=7, bg=3, key=0, d=PLANE, ds=320)
    do(s, FILL, w=0, h=0, x0=5, y0=5, **base)
    do(s, FILL, w=0, h=9, x0=5, y0=5)
    do(s, FILL, w=9, h=0)
    do(s, FILL, w=10, h=10, x0=1000, y0=0)  # fully clipped (right of the buffer)
    do(s, FILL, w=10, h=10, x0=-5, y0=-5)  # negative corner, partly visible
    do(s, FILL, w=10, h=10, x0=-10, y0=-10)  # touching nothing
    do(s, FILL, w=10, h=10, x0=315, y0=195, color=9)  # off the right and bottom edge
    do(s, FILL, w=65535, h=2, x0=-30000, y0=198)  # huge, mostly outside
    do(s, FILL, w=40, h=40, x0=10, y0=10, con=CLIP, cx=20, cy=20, cw=0, ch=10)  # empty clip
    do(s, FILL, cw=10, ch=10, x0=0, y0=0, w=30, h=30)
    do(s, FILL, cx=0, cy=0, cw=1000, ch=1000, ds=400, w=50, h=290, y0=0)  # fullscreen stride: 280 rows
    do(s, FILL, ds=320, con=0, w=50, h=290, y0=-3)  # 200 rows
    halftone(s, [0] * 16)
    do(s, FILL, con2=0, w=40, h=20, x0=3, y0=3)  # all-zero pattern, not declared: sniffed -> plain
    do(s, FILL, con2=mm.CON2_HALFTONE_EN, bg=3)  # declared: density 0 -> BG
    halftone(s, [0xAAAA, 0x5555] * 8)
    do(s, FILL, con2=0, x0=-4, y0=-3)
    do(s, FILL, con2=mm.CON2_FILL_MT, mt=mm.MT_XOR_BC)
    do(s, FILL, mt=mm.MT_OR_BC, con2=mm.CON2_FILL_MT | mm.CON2_HALFTONE_EN)
    do(s, FILL, mt=mm.MT_B, con2=mm.CON2_FILL_MT)
    do(s, FILL, mt=mm.MT_XOR_BC, con2=0)  # FILL ignores MINTERM without FILL_MT


def lines(s: Script) -> None:
    base = regs(mt=mm.MT_B, con=CLIP, con2=0, color=5, d=PLANE, ds=320, cx=20, cy=30, cw=100, ch=60)
    do(s, LINE, x0=20, y0=30, x1=20, y1=89, **base)  # along the left clip edge
    do(s, LINE, x0=119, y0=30, x1=119, y1=89)  # along the right edge
    do(s, LINE, x0=19, y0=0, x1=19, y1=120)  # one pixel outside
    do(s, LINE, x0=120, y0=0, x1=120, y1=120)
    do(s, LINE, x0=0, y0=89, x1=200, y1=89)  # along the bottom row
    do(s, LINE, x0=0, y0=90, x1=200, y1=90)
    do(s, LINE, x0=50, y0=50, x1=50, y1=50)  # one pixel
    do(s, LINE, x0=60, y0=40, x1=30, y1=80)  # right to left, down
    do(s, LINE, x0=30, y0=80, x1=60, y1=40, mt=mm.MT_XOR_BC)
    do(s, LINE, x0=0, y0=0, x1=300, y1=7, mt=mm.MT_B)  # shallow: the tie-break
    do(s, LINE, x0=0, y0=0, x1=7, y1=300)  # steep
    do(s, LINE, x0=0, y0=0, x1=11, y1=11)  # exact diagonal
    do(s, LINE, x0=-100, y0=-100, x1=400, y1=300, con=0)  # through the whole screen, no clip rect
    do(s, LINE, x0=-32768, y0=100, x1=32767, y1=101)  # extreme: 65536 steps
    do(s, LINE, x0=10, y0=10, x1=130, y1=10, con=0, ds=400, mt=mm.MT_OR_BC)


def triangles(s: Script) -> None:
    base = regs(mt=mm.MT_B, con=0, con2=0, color=6, bg=2, d=PLANE, ds=320)
    do(s, TRI, x0=10, y0=10, x1=60, y1=20, x2=30, y2=70, **base)
    do(s, TRI, x0=10, y0=10, x1=10, y1=10, x2=10, y2=10)  # one point
    do(s, TRI, x0=10, y0=10, x1=40, y1=40, x2=70, y2=70)  # collinear
    do(s, TRI, x0=10, y0=30, x1=60, y1=30, x2=100, y2=30)  # flat (zero height)
    do(s, TRI, x0=10, y0=10, x1=50, y1=10, x2=30, y2=60)  # flat top edge
    do(s, TRI, x0=10, y0=60, x1=50, y1=60, x2=30, y2=10)  # flat bottom edge
    do(s, TRI, x0=30, y0=10, x1=10, y1=60, x2=50, y2=60)  # winding the other way
    do(s, TRI, x0=-50, y0=-50, x1=400, y1=60, x2=100, y2=300)  # bigger than the screen
    do(s, TRI, x0=-20, y0=-20, x1=-5, y1=-5, x2=-30, y2=-1)  # entirely off to the top left
    do(s, TRI, x0=0, y0=0, x1=319, y1=0, x2=0, y2=199)  # the screen's corners
    do(s, TRI, x0=0, y0=0, x1=319, y1=199, x2=0, y2=199, mt=mm.MT_XOR_BC)
    do(s, TRI, x0=10, y0=10, x1=100, y1=15, x2=40, y2=90, con=CLIP, cx=30, cy=20, cw=40, ch=30)
    do(s, TRI, x0=10, y0=10, x1=100, y1=15, x2=40, y2=90, cw=0)  # empty clip
    halftone(s, [0xF0F0] * 16)
    do(s, TRI, x0=10, y0=10, x1=100, y1=15, x2=40, y2=90, con=0, con2=mm.CON2_HALFTONE_EN, mt=mm.MT_B)
    do(s, TRI, x0=-9, y0=3, x1=22, y1=-5, x2=3, y2=20, mt=mm.MT_OR_BC)  # a thin one, negative slopes


def blits(s: Script) -> None:
    base = regs(
        mt=mm.MT_B,
        con=mm.CON_USEB,
        con2=0,
        key=2,
        d=PLANE,
        ds=320,
        a=PLANE + 64000,
        as_=320,
        b=PLANE + 128000,
        bs=320,
        x0=10,
        y0=10,
        w=20,
        h=15,
    )
    do(s, BLIT, **base)
    do(s, BLIT, w=0, h=5)
    do(s, BLIT, w=5, h=0)
    do(s, BLIT, w=40, h=30, x0=-10, y0=-8)  # negative origin: clipped on two sides
    do(s, BLIT, w=40, h=30, x0=300, y0=190)
    do(s, BLIT, con=mm.CON_USEB | mm.CON_KEY_EN, key=0, w=30, h=20, x0=2, y0=2)
    do(s, BLIT, con=mm.CON_KEY_EN, key=0)  # key on, B off: B reads as 0 == key: nothing drawn
    do(s, BLIT, con=mm.CON_KEY_EN, key=1)
    do(s, BLIT, con=7, mt=mm.MT_COOKIE, key=0)  # a cookie-cut bob
    do(s, BLIT, con=7 | mm.CON_CLIP_EN, mt=0xEA, cx=12, cy=12, cw=15, ch=9)
    for b, con in ((130, 0), (130, DESC), (70, 0), (70, DESC)):  # overlapping moves, both ways, both orders
        s.lines.append("seed 9")  # fresh data: a move leaves it shifted onto itself, and DESC would not show
        do(
            s,
            BLIT,
            con=mm.CON_USEB | con,
            d=PLANE + 100,
            b=PLANE + b,
            bs=320,
            ds=320,
            mt=mm.MT_B,
            w=60,
            h=4,
            x0=0,
            y0=0,
        )
    # Smears: the source one pixel / one row behind the destination in the walk order, so each
    # pixel reads the byte the one before it (or the row before it) has just written. The pixel
    # unit must not read ahead of those writes (zm_blit_chk `overlap`, zm_blit_px `ordered`).
    smears = ((mm.CON_USEB, 99, 40, 3, 0), (mm.CON_USEB, 101, 40, 3, DESC), (mm.CON_USEA, 99, 24, 2, 0))
    smears += ((mm.CON_USEA, 100 - 320, 8, 6, 0), (mm.CON_USEB, 100 + 320, 8, 6, DESC))
    for use, src, w, h, con in smears:
        s.lines.append("seed 9")
        a, b = (PLANE + src, 0) if use == mm.CON_USEA else (0, PLANE + src)
        mt = mm.MT_A if use == mm.CON_USEA else mm.MT_B
        do(s, BLIT, con=use | con, d=PLANE + 100, a=a, b=b, as_=320, bs=320, ds=320, mt=mt, w=w, h=h, x0=0, y0=0)
    do(s, BLIT, con=mm.CON_USEB, mt=mm.MT_B, b=mm.REGION_BYTES - 10, w=11, h=1)  # reads one byte past the region
    do(s, BLIT, b=mm.REGION_BYTES - 11, w=11, h=1)  # ... exactly to its end
    do(s, BLIT, b=mm.REGION_BYTES - 5, bs=1000, w=2, h=1)
    abs_ = regs(con=mm.CON_USEB, con2=mm.CON2_SRC_ABS, w=16, h=4, x0=0, y0=0, mt=mm.MT_B)
    do(s, BLIT, b=mm.CART_RAM_BASE, bs=64, **abs_)
    do(s, BLIT, b=mm.CART_RAM_TOP - 16 - 3 * 64)  # ends exactly at the window's top
    do(s, BLIT, b=mm.CART_RAM_TOP - 16 - 3 * 64 + 1)  # one byte over: crosses into the video region
    do(s, BLIT, b=mm.ROM_RAM_BASE, bs=16)
    do(s, BLIT, b=mm.ROM_RAM_TOP - 16 - 3 * 16)
    do(s, BLIT, b=mm.ROM_RAM_TOP - 16 - 3 * 16 + 1)
    do(s, BLIT, b=mm.ROM_RAM_BASE - 8, bs=16)  # starts in the gap
    do(s, BLIT, b=mm.HW_VIDEO_BASE + PLANE, bs=320)
    do(s, BLIT, b=mm.HW_VIDEO_BASE + mm.REGION_BYTES - 16 - 3 * 64, bs=64)
    do(s, BLIT, b=mm.HW_VIDEO_BASE + mm.REGION_BYTES - 15 - 3 * 64, bs=64)  # one byte over
    do(s, BLIT, b=0x1_0000_0000 - 8, bs=64)  # wraps around 2^32
    do(
        s,
        BLIT,
        con=7 | mm.CON_DESC,
        a=mm.CART_RAM_BASE + 100,
        as_=33,
        b=mm.CART_RAM_BASE + 3000,
        bs=17,
        mt=mm.MT_COOKIE,
    )


def dest_bounds(s: Script) -> None:
    base = regs(mt=mm.MT_B, con=0, con2=0, color=9, ds=320, w=4, h=1, x0=316, y0=199)
    last = 199 * 320 + 320  # the last byte after the box
    for delta in (0, 1, -1):
        do(s, FILL, d=mm.REGION_BYTES - last + delta, **base)
    do(s, FILL, d=0xFFFF_FFF0)
    do(s, LINE, d=mm.REGION_BYTES - last + 1, x0=0, y0=199, x1=319, y1=199)
    do(s, LINE, d=mm.REGION_BYTES - last, x0=0, y0=199, x1=319, y1=199)
    do(s, TRI, d=mm.REGION_BYTES - last + 1, x0=300, y0=198, x1=319, y1=199, x2=310, y2=199)
    do(s, FILL, d=mm.REGION_BYTES - 400 * 280, ds=400, w=400, h=280, x0=0, y0=0)  # a whole fullscreen plane at the end
    do(s, FILL, d=mm.REGION_BYTES - 400 * 280 + 1)


def edge_script() -> Script:
    s = Script(77)
    for part in (fills, lines, triangles, blits, dest_bounds):
        part(s)
    do(s, 0)  # NOP
    do(s, 5)  # unknown commands draw nothing and report 0
    do(s, 200)
    return s
