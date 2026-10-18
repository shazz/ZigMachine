"""Blitter script for tests/test_blit_dcache.py: the ops where a range that is one byte or one
clip edge short would show, which random ops rarely produce. COLOR is 0x5A, a byte the seeded
memory never holds, so every pixel an op draws changes and must be covered:
- steep lines whose LAST point (vertex 1) is the box's right or bottom edge and starts a cache line
  (the plane's rows are line-aligned: OFF_VRAM and 320 are multiples of 32), so that pixel is alone
  in its line;
- triangles whose right-most vertex is vertex 1 or 2;
- a clip window with its origin inside the plane (the box's right and bottom edges come from it);
- a frame of 16x16 tiles (the Union hub's ~500 small ops), aligned and across lines;
- a full-plane clear (the whole-cache fallback)."""

from blitter_scripts import BLIT, CLIP, FILL, LINE, PLANE, TRI, Script, mm

INK = 0x5A


def _regs(s: Script, con: int = 0, stride: int = 320) -> None:
    s.w(8, mm.BLIT_MINTERM, mm.MT_B)
    s.w(8, mm.BLIT_CON, con)
    s.w(8, mm.BLIT_CON2, 0)
    s.w(8, mm.BLIT_COLOR, INK)
    s.w(32, mm.BLIT_D_BASE, PLANE)
    s.w(16, mm.BLIT_D_STRIDE, stride)
    for k in range(16):
        s.w(16, mm.BLIT_HALFTONE + 2 * k, 0)


def _run(s: Script, cmd: int, pts: list[tuple[int, int]], w: int = 0, h: int = 0) -> None:
    for k, (x, y) in enumerate(pts):
        s.w(16, mm.BLIT_X0 + 4 * k, x & 0xFFFF)
        s.w(16, mm.BLIT_Y0 + 4 * k, y & 0xFFFF)
    s.w(16, mm.BLIT_W, w)
    s.w(16, mm.BLIT_H, h)
    s.lines.append(f"run {cmd}")


def dinval_script() -> Script:
    s = Script(7)
    _regs(s)
    for x in (32, 64, 128, 288):
        _run(s, LINE, [(x - 3, 40), (x, 90)])  # steep, down-right: (x, 90) alone in its line
        _run(s, LINE, [(x - 3, 150), (x, 100)])  # up-right: the end is the right edge, not the bottom
    for x in (96, 160):
        _run(s, TRI, [(x - 40, 20), (x, 60), (x - 30, 80)])  # right-most vertex 1
        _run(s, TRI, [(x - 40, 120), (x - 20, 125), (x, 170)])  # right-most and lowest vertex 2
    _regs(s, CLIP)
    for cx, cy, cw, ch in ((100, 50, 40, 30), (33, 7, 64, 9), (250, 150, 70, 50)):
        for k, v in enumerate((cx, cy, cw, ch)):
            s.w(16, mm.BLIT_CLIP_X + 2 * k, v)
        _run(s, FILL, [(0, 0)], 320, 200)  # clipped to the window: a range, edges from the clip
    _regs(s)
    s.w(32, mm.BLIT_B_BASE, PLANE + 64000)  # a tile sheet in the next plane
    s.w(16, mm.BLIT_B_STRIDE, 320)
    s.w(8, mm.BLIT_CON, mm.CON_USEB)
    for ty in range(0, 64, 16):
        for tx in range(0, 320, 16):
            _run(s, BLIT, [(tx + (ty // 16) * 5, ty)], 16, 16)  # rows 1-3 shifted off line alignment
    s.w(8, mm.BLIT_CON, 0)
    _run(s, FILL, [(0, 0)], 320, 200)  # a clear: the whole-cache fallback
    return s
