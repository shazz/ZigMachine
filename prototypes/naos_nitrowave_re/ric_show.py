"""F1 as the shifter shows it: a low-res screen (160-byte lines, bottom
border opened by the Timer B handler), colours 0 and 1 changed every line
from the table at $47524 by Timer B ($E08), the logo palette ($782AA) from
the 60th line on; colour 0 is the side borders' colour too.

Palette registers are a state carried from frame to frame (Regs)."""
import numpy as np

from stimg import chunky, st_rgb

TABLE = 0x47524
TOP_ROW = 29  # capture row of line 0 (the normal window: x 48..367, rows 29..228)
LEFT = 48
LINES = 247  # 200 + the opened bottom border down to capture row 275


class Regs:
    def __init__(self, words):
        self.p = list(words)

    def vbl(self, mem):
        """$101A..$104C: colours 3, 5 .. 13 from $68C2, colour 1 from the
        scroller's colour list as it stands before the VBL moves it on."""
        for k, c in enumerate((3, 5, 7, 9, 11, 13)):
            self.p[c] = int.from_bytes(mem[0x68C2 + 6 + 4 * k:0x68C8 + 4 * k], 'big')
        a1 = int.from_bytes(mem[int.from_bytes(mem[0x4790E:0x47912], 'big'):][:4], 'big')
        self.p[1] = int.from_bytes(mem[a1:a1 + 2], 'big')

    def hbl(self, mem, k):
        """Timer B's k-th interrupt (k = 1 at the end of line 0)."""
        at = TABLE + 4 * (k - 1)
        self.p[0] = int.from_bytes(mem[at:at + 2], 'big')
        self.p[1] = int.from_bytes(mem[at + 2:at + 4], 'big')
        if k == 60:  # the count reaches $8A
            for j, c in enumerate((3, 5, 7, 9, 11, 13)):
                self.p[c] = int.from_bytes(mem[0x782AA + 6 + 4 * j:0x782B0 + 4 * j], 'big')


def frame(mem, shown, regs, hbl_shift=0):
    """Capture-space RGB of the frame whose VBL just ran (palette state in
    `regs` carried across frames). Line L shows after hbl(L + hbl_shift)."""
    out = np.zeros((276, 416, 3), np.uint8)
    top = st_rgb(regs.p[0])
    out[:TOP_ROW] = top
    for line in range(LINES):
        k = line + hbl_shift
        if k >= 1:
            regs.hbl(mem, k)
        pal = np.array([st_rgb(w) for w in regs.p], np.uint8)
        y = TOP_ROW + line
        if y >= 276:
            break
        out[y] = pal[0]
        idx = chunky(mem, shown + 160 * line, 160, 1, 320)[0]
        out[y, LEFT:LEFT + 320] = pal[idx]
    return out
