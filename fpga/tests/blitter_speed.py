"""In-plane copies whose speed the oracle cannot see: a copy runs `ordered` (each pixel's reads
wait for every earlier write) or not, and both leave the same pixels. test_rtl_blitter.py runs
this script in `fast` memory mode and bounds the clocks per pixel of each op, so a check that
is merely too careful (the plane's base as the destination span's start, SOC_REVIEW F5) fails
here, while one that is too bold fails the hash in `random`/`deep` mode.

Each entry: (name, fast?) — fast ops must run near a pixel a clock, ordered ones must not."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from blitter_scripts import BLIT, DESC, PLANE, Script, do, mm, regs

W, H = 64, 32
COPY = mm.CON_USEB


def speed_script() -> tuple[Script, list[tuple[str, bool]]]:
    s = Script(7)
    ops: list[tuple[str, bool]] = []

    def copy(name: str, fast: bool, src: int, x0: int, y0: int, con: int = COPY, bs: int = 320, h: int = H) -> None:
        do(s, BLIT, b=src, bs=bs, x0=x0, y0=y0, con=con, h=h, con2=mm.CON2_MIRROR_X if "mirror" in name else 0)
        ops.append((name, fast))

    do(s, BLIT, **regs(mt=mm.MT_B, con=COPY, con2=0, key=0, d=PLANE, ds=320, w=W, h=H, x0=0, y0=0, b=PLANE + 100 * 320, bs=320))
    ops.append(("warm-up, source below the box", True))
    # rows 0..31 copied to rows 100..131: the source lies above the box, in the same plane
    copy("strip above the box", True, PLANE, 10, 100)
    # one row copied down, h = 1 (dbug's blitRow): another row of the same plane
    copy("one row to a lower row", True, PLANE + 5 * 320, 10, 150, h=1)
    # scroll up by a row: overlapping, source one row ahead of the ascending walk
    copy("scroll up (delta +stride)", True, PLANE + 21 * 320, 0, 20)
    # scroll left by a pixel: overlapping, one byte ahead
    copy("scroll left (delta +1)", True, PLANE + 40 * 320 + 1, 0, 40)
    # scroll down with DESC: overlapping, one row behind a descending walk
    copy("scroll down DESC (delta -stride)", True, PLANE + 59 * 320, 0, 60, con=COPY | DESC)
    # smear right: one byte behind an ascending walk, every read must see the last write
    copy("smear right (delta -1)", False, PLANE + 80 * 320 - 1, 0, 80)
    # scroll down without DESC: the source is the rows just written
    copy("scroll down ascending (delta -stride)", False, PLANE + 119 * 320, 0, 120)
    # another stride: its delta shrinks a row at a time, so it reads behind the walk
    copy("overlap, other stride", False, PLANE + 160 * 320 + 2, 0, 160, bs=310)
    # mirrored over itself one byte ahead: no constant offset, so the walk does read behind itself
    copy("mirror X over itself (ordered)", False, PLANE + 168 * 320 + 1, 0, 168)
    return s, ops
