"""vicmodel.py: a line-level VIC-II sprite model, driven by capture.py's snapshot + trace.

Rules (C. Bauer, "The MOS 6567/6569 video controller", sec. 3.8, cycle numbers = VICE's
trace numbering + OFS): per line L
  c15/16  if the Y-expansion flip-flop is set: MCBASE <- MC; if MCBASE == 63 DMA off
  c55     a sprite with MxYE set inverts its flip-flop
  c55/56  enabled, DMA off and Y == L&$FF: DMA on, MCBASE = 0, flip-flop cleared if MxYE
  c58     MC <- MCBASE; if DMA on, the sprite's row MC/3 is fetched and shown on line L+1
  while MxYE is 0 the flip-flop is held set (so a $D017 0-then-mask write per line makes
  the masked sprites repeat a row: the "stretch").
Registers are applied at their cycle; a sprite line is drawn with the registers as they are
at the cycle the beam reaches its X. The vertical border is open (both parts 1 and 3 open
it); side borders are open on lines where $D016 is DEC/INC'd (part 3)."""
import sys

from PIL import Image

OFS = 1  # VICE trace cycle + OFS = Bauer cycle (calibrated)
PAL = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x96, 0x28, 0x2E), (0x5B, 0xD6, 0xCE),
       (0x9F, 0x2D, 0xAD), (0x41, 0xB9, 0x36), (0x27, 0x24, 0xC4), (0xEF, 0xF3, 0x47),
       (0x9F, 0x48, 0x15), (0x5E, 0x35, 0x00), (0xDA, 0x5F, 0x66), (0x47, 0x47, 0x47),
       (0x78, 0x78, 0x78), (0x91, 0xFF, 0x84), (0x68, 0x64, 0xFF), (0xAE, 0xAE, 0xAE)]
CHARGEN = open(__import__("os").path.expanduser("~/.local/c64/share/vice/C64/chargen-901225-01.bin"), "rb").read()
FIRST_ROW = 16  # screenshot row 0 = raster line 16
W, H = 384, 272


def load(base: str) -> tuple[bytearray, bytearray, list[tuple[int, int, int, str]]]:
    ram = bytearray(open(base + ".ram", "rb").read())
    vic = bytearray(open(base + ".vic", "rb").read())
    ev = []
    for ln in open(base + ".trace"):
        line, cyc, addr, val = ln.split()
        ev.append((int(line), int(cyc) + OFS, int(addr, 16), val))
    return ram, vic, ev


class Vic:
    def __init__(self, ram: bytearray, vic: bytearray, bank: int, screen: int) -> None:
        self.ram, self.reg = ram, vic
        self.bank, self.screen = bank, screen
        self.dma = [False] * 8
        self.ff = [True] * 8
        self.mcbase = [63] * 8
        self.mc = [63] * 8
        self.fetched: list[bytes | None] = [None] * 8  # row shown on the next line
        self.side_open_lines: set[int] = set()

    def write(self, line: int, cyc: float, addr: int, val: str) -> None:
        if addr >= 0xD000 and addr <= 0xD02E:
            r = addr - 0xD000
            if r == 0x16:
                # 38 columns between the X=335 and X=344 compares (VICE cycles 55..56) misses
                # both: the right border stays open. Earlier (the loop's catch-up lines after
                # a band change) the 38-column compare closes it; the INC at c20 restores.
                if 55 <= cyc - OFS <= 56:
                    self.side_open_lines.add(line)
                return
            if val in ("RMW", "??"):
                return
            self.reg[r] = int(val, 16)
            if r == 0x17:
                for i in range(8):
                    if not self.reg[0x17] >> i & 1:
                        self.ff[i] = True
        elif val not in ("RMW", "??"):
            self.ram[addr] = int(val, 16)

    def vread(self, a: int) -> int:
        """What the VIC sees at bank offset a: banks 0 and 2 map the char ROM at $1000."""
        if self.bank in (0, 0x8000) and 0x1000 <= a < 0x2000:
            return CHARGEN[a - 0x1000]
        return self.ram[self.bank + a]

    def c16(self) -> None:
        for i in range(8):
            if self.ff[i]:
                self.mcbase[i] = self.mc[i]
                if self.mcbase[i] >= 63:
                    self.dma[i] = False

    def c55(self, line: int) -> None:
        for i in range(8):
            if self.reg[0x17] >> i & 1:
                self.ff[i] = not self.ff[i]
        for i in range(8):
            if (self.reg[0x15] >> i & 1) and not self.dma[i] and self.reg[1 + 2 * i] == line & 0xFF:
                self.dma[i] = True
                self.mcbase[i] = 0
                if self.reg[0x17] >> i & 1:
                    self.ff[i] = False

    def fetch(self, i: int) -> None:
        self.mc[i] = self.mcbase[i]
        if not self.dma[i]:
            self.fetched[i] = None
            return
        ptr = self.vread(self.screen + 0x3F8 + i)
        a = ptr * 64 + self.mc[i]
        self.fetched[i] = bytes(self.vread(a + j) for j in range(3))
        self.mc[i] += 3


def x_of(reg: bytearray, i: int) -> int:
    return reg[2 * i] | ((reg[0x10] >> i & 1) << 8)


def draw_sprite(img: list[list[int | None]], row: int, reg: bytearray, i: int, data: bytes) -> None:
    x0 = x_of(reg, i)
    bits = data[0] << 16 | data[1] << 8 | data[2]
    mcol = reg[0x1C] >> i & 1
    xe = 2 if reg[0x1D] >> i & 1 else 1
    cols = [None, reg[0x25] & 15, reg[0x27 + i] & 15, reg[0x26] & 15]
    for p in range(24):
        if mcol:
            v = bits >> (22 - (p & ~1)) & 3
            c = cols[v]
        else:
            c = (reg[0x27 + i] & 15) if bits >> (23 - p) & 1 else None
        if c is None:
            continue
        for e in range(xe):
            col = (x0 + p * xe + e + 8) % 504  # PAL: X $1F0 is the column left of X 0
            if 0 <= col < W and img[row][col] is None:
                img[row][col] = c


def run(base: str, bank: int, screen: int, vb_closed: bool = False) -> list[list[int]]:
    ram, vic, ev = load(base)
    v = Vic(ram, vic, bank, screen)
    vb = vb_closed
    vb_line = {}
    border = [[0] * W for _ in range(H)]  # border colour per line (end of line)
    spr: list[list[int | None]] = [[None] * W for _ in range(H)]
    lines = list(range(288, 312)) + list(range(0, 288))
    k = 0
    for line in lines:
        # sprites 3..7 fetch at the start of this line (Bauer c1..c10): show on this line
        todo = sorted([(c, a, val) for (ln, c, a, val) in ev[k:] if ln == line], key=lambda t: t[0])
        while k < len(ev) and ev[k][0] == line:
            k += 1
        row = line - FIRST_ROW
        shown = list(v.fetched)
        # vertical border compares act from the start of the line, with $D011 as it is then
        rsel = v.reg[0x11] >> 3 & 1
        if line == (251 if rsel else 247):
            vb = True
        if line == (51 if rsel else 55) and v.reg[0x11] & 0x10:
            vb = False
        vb_line[line] = vb
        events = todo + [(15.5, "c16", None), (55, "c55", None), (58, "fetch", None)]
        events.sort(key=lambda t: (t[0], 0 if isinstance(t[1], int) else 1))
        reg_at_draw = None
        for c, a, val in events:
            if a == "c16":
                v.c16()
            elif a == "c55":
                v.c55(line)
            elif a == "fetch":
                if 0 <= row < H:
                    reg_at_draw = bytearray(v.reg)
                for i in range(8):
                    v.fetch(i)
            else:
                v.write(line, c, a, val)
        if 0 <= row < H:
            border[row] = [v.reg[0x20] & 15] * W
            for i in range(8):
                if shown[i] is not None:
                    draw_sprite(spr, row, reg_at_draw, i, shown[i])
    return compose(border, spr, v.side_open_lines, vb_line)


def compose(border: list[list[int]], spr: list[list[int | None]], side: set[int],
            vb_line: dict[int, bool]) -> list[list[int]]:
    """Main border: closed on the whole line under the vertical border; else the right
    border opens on a line whose $D016 trick ran, the left border on the line after one."""
    out = []
    for row in range(H):
        line = row + FIRST_ROW
        r = []
        for col in range(W):
            s = spr[row][col]
            if vb_line[line]:
                inside = False
            elif col < 32:
                inside = (line - 1) in side
            elif col >= 352:
                inside = line in side
            else:
                inside = True
            r.append(s if (s is not None and inside) else border[row][col])
        out.append(r)
    return out


def png_indices(path: str) -> list[list[int]]:
    im = Image.open(path).convert("RGB")
    lut = {c: i for i, c in enumerate(PAL)}
    px = im.load()
    return [[lut.get(px[x, y], -1) for x in range(W)] for y in range(H)]


def diff(a: list[list[int]], b: list[list[int]]) -> tuple[int, tuple[int, int, int, int] | None]:
    bad = [(x, y) for y in range(H) for x in range(W) if a[y][x] != b[y][x]]
    if not bad:
        return 0, None
    xs, ys = [p[0] for p in bad], [p[1] for p in bad]
    return len(bad), (min(xs), min(ys), max(xs), max(ys))


def save(idx: list[list[int]], path: str) -> None:
    im = Image.new("RGB", (W, H))
    im.putdata([PAL[c] for r in idx for c in r])
    im.save(path)


def bank_screen(base: str, vic: bytes) -> tuple[int, int]:
    dd00 = open(base + ".cia", "rb").read()[0]
    return (3 - (dd00 & 3)) * 0x4000, (vic[0x18] >> 4) * 0x400


if __name__ == "__main__":
    base = sys.argv[1]
    bank, screen = bank_screen(base, open(base + ".vic", "rb").read())
    ref = png_indices(base + ".png")
    model = run(base, bank, screen)
    n, box = diff(model, ref)
    if n:
        model = run(base, bank, screen, True)
        n, box = diff(model, ref)
    print(base, "mismatch", n, box)
    if len(sys.argv) > 2:
        save(model, sys.argv[2])
