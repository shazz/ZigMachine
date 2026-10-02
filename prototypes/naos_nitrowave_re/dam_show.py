"""F3's picture as the shifter shows it: the screen in RAM through the colour
registers as the VBL program changes them along each line.

Writes (pal_writes.py / gen_layout.py, Hatari's variant $164/$34/2 nops):
  end of the VBL: all 16 from $361BE (black): the top border, and colours 2..15
                  until block 1 (header, before line 0)
  every line L:   colour 0 at cycle 42, colour 1 at 54 (line 228: 26, 38), from
                  the table a2 = $5F24 (two words a line)
  blocks:         colours 2..15 at (line, cycle) below
Capture x of a write at cycle c = c + K (fitted: dam_fit.py)."""
import struct

import numpy as np

from stimg import chunky, st_rgb

BLOCK1 = [0x210, 0x210, 0x776, 0x776, 0x321, 0x321, 0x432, 0x432, 0x542, 0x542, 0x654, 0x654, 0x765, 0x765]
# (line, cycle, colour, value) of the three later blocks, from pal_writes.py
BLOCKS = [(80, 422, 2, 0x643), (80, 458, 3, 0x754), (80, 474, 4, 0x433), (80, 490, 5, 0x532),
          (81, 20, 6, 0x643), (81, 86, 7, 0x754), (81, 102, 8, 0x655), (81, 118, 9, 0x532),
          (81, 134, 10, 0x643), (81, 150, 11, 0x754), (81, 166, 12, 0x544), (81, 182, 13, 0x532),
          (81, 198, 14, 0x643), (81, 214, 15, 0x754),
          (145, 414, 4, 0x34), (145, 458, 5, 0x34), (145, 474, 6, 0x34), (145, 490, 7, 0x34),
          (146, 20, 8, 0x45), (146, 86, 9, 0x45), (146, 102, 10, 0x45), (146, 118, 11, 0x45),
          (146, 134, 12, 0x156), (146, 150, 13, 0x156), (146, 166, 14, 0x156), (146, 182, 15, 0x156),
          (178, 414, 2, 0x100), (178, 458, 3, 0x100), (178, 474, 4, 0x201), (178, 490, 5, 0x201),
          (179, 20, 6, 0x312), (179, 86, 7, 0x312), (179, 102, 8, 0x423), (179, 118, 9, 0x423),
          (179, 134, 10, 0x534), (179, 150, 11, 0x534), (179, 166, 12, 0x645), (179, 182, 13, 0x645),
          (179, 198, 14, 0x756), (179, 214, 15, 0x756)]
LINES = 256
LINE_CYCLES = 512


def events(mem):
    """(line, cycle, colour, value) of every write that reaches a visible line."""
    table = struct.unpack('>512H', bytes(mem[0x5F24:0x5F24 + 1024]))
    ev = []
    for line in range(LINES):
        c0, c1 = (26, 38) if line == 228 else (42, 54)
        ev += [(line, c0, 0, table[2 * line]), (line, c1, 1, table[2 * line + 1])]
    ev += BLOCKS
    ev.sort(key=lambda e: (e[0], e[1]))
    return ev


SHOWN_LINES = 255  # line 255 shows black (Hatari capture)
BORDER_X = 412  # capture x 412..415: the right border, colour 0 as it stands


def image(mem, shown, k, first_row=1, rows=276, width=BORDER_X, line_x0=4):
    """Capture-space RGB: row y shows line y - first_row from line pixel x + line_x0."""
    pal = [0] * 2 + BLOCK1
    out = np.zeros((rows, 416, 3), np.uint8)
    ev = events(mem)
    e = 0
    for y in range(rows):
        line = y - first_row
        if line < 0 or line >= SHOWN_LINES:
            continue
        idx = chunky(mem, shown + 160 + 230 * line, 240, 1, 480)[0][line_x0:line_x0 + width]
        x = 0
        while x < width:
            while e < len(ev) and (ev[e][0], ev[e][1] + k) <= (line, x):
                pal[ev[e][2]] = ev[e][3]
                e += 1
            nxt = width
            if e < len(ev) and ev[e][0] == line:
                nxt = min(width, max(x + 1, ev[e][1] + k))
            rgb = np.array([st_rgb(w) for w in pal], np.uint8)
            out[y, x:nxt] = rgb[idx[x:nxt]]
            x = nxt
        out[y, width:] = st_rgb(pal[0])
    return out
