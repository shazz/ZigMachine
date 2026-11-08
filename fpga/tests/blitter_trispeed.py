"""TRIANGLE clocks: a few triangles whose clocks test_rtl_blitter.py bounds (the edge walk's
setup and per-row cost), and which the report compares with v1's per-row divide.
Each entry: (name, rows, hidden): the rows it spans on the plane and above it (the walk crosses
those too, two clocks a row an edge), MT_B, no clip, 320 stride."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from blitter_scripts import PLANE, TRI, Script, do, mm, regs

# (name, rows, hidden, vertices): small, medium, large, a sliver, one clipped at the top
SHAPES = [
    ("small 10 rows", 10, 0, (100, 50, 112, 55, 104, 60)),
    ("medium 50 rows", 50, 0, (40, 20, 120, 45, 70, 70)),
    ("large 180 rows", 180, 0, (10, 10, 310, 100, 150, 190)),
    ("sliver 150 rows", 150, 0, (200, 20, 201, 170, 203, 90)),
    ("clipped top 100 rows, 3000 above", 100, 3000, (60, -3000, 250, 99, 20, 60)),
]


def trispeed_script() -> tuple[Script, list[tuple[str, int, int]]]:
    s = Script(11)
    base = regs(mt=mm.MT_B, con=0, con2=0, color=9, bg=0, d=PLANE, ds=320)
    for k, (_, _, _, (x0, y0, x1, y1, x2, y2)) in enumerate(SHAPES):
        kw = dict(base) if k == 0 else {}
        do(s, TRI, x0=x0, y0=y0 & 0xFFFF, x1=x1, y1=y1, x2=x2, y2=y2, **kw)
    return s, [(n, rows, hidden) for n, rows, hidden, _ in SHAPES]
