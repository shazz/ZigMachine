"""The randomised blitter ops: a Script (blitter_scripts.py) that draws FILL, BLIT, LINE and
TRIANGLE with random geometry, around the clip rect, at the region boundaries."""

from blitter_scripts import BLIT, FILL, LINE, MINTERMS, PLANE, TRI, WINDOWS, Script, mm


class RandomScript(Script):
    def fill(self) -> None:
        r = self.r
        self.common(
            FILL,
            r.choice(MINTERMS),
            r.choice([0, mm.CON_CLIP_EN, mm.CON_CLIP_EN, mm.CON_USEB]),
            r.choice([0, mm.CON2_FILL_MT, mm.CON2_HALFTONE_EN, mm.CON2_FILL_MT | mm.CON2_HALFTONE_EN]),
        )
        w, h = r.choice([self.size()] * 15 + [(65535, 2), (3, 65535)])
        x, y = self.xy()
        for off, v in ((mm.BLIT_W, w), (mm.BLIT_H, h), (mm.BLIT_X0, x), (mm.BLIT_Y0, y)):
            self.w(16, off, v, 0.95)
        self.boundary(
            self.get(mm.BLIT_X0, 16, True),
            self.get(mm.BLIT_Y0, 16, True),
            self.get(mm.BLIT_X0, 16, True) + self.get(mm.BLIT_W),
            self.get(mm.BLIT_Y0, 16, True) + self.get(mm.BLIT_H),
        )
        self.run()

    def source(self, base_off: int, stride_off: int, absolute: bool, w: int, h: int) -> None:
        r = self.r
        stride = r.choice([w, 320, 400, r.randint(1, 500), 0])
        need = max(h - 1, 0) * stride + w
        lo, hi = r.choice(WINDOWS) if absolute else (0, mm.REGION_BYTES)
        if absolute and r.random() < 0.1:  # straddling a window boundary or the gap: must be refused
            base = r.choice([lo - r.randint(1, need + 1), hi - r.randint(1, need + 1)])
        else:
            base = lo + (
                r.randrange(max(hi - lo - need, 1)) if absolute else r.randrange(PLANE, max(hi - need, PLANE + 1))
            )
        if r.random() < 0.1:  # right at the limit
            base = hi - need + r.choice([-1, 0, 1])
        self.w(32, base_off, base & 0xFFFFFFFF, 0.95)
        self.w(16, stride_off, stride, 0.95)

    def blit(self) -> None:
        r = self.r
        use = r.choice([2, 2, 2, 3, 6, 7, 1, 0, 4, 5])  # USEA | USEB | USEC
        con = use | r.choice([0, mm.CON_KEY_EN]) | r.choice([0, mm.CON_DESC]) | r.choice([0, mm.CON_CLIP_EN])
        absolute = r.random() < 0.3
        self.common(BLIT, r.choice(MINTERMS + [mm.MT_B] * 3), con, mm.CON2_SRC_ABS if absolute else 0)
        (w, h), (x, y) = self.size(), self.xy()
        for off, v in ((mm.BLIT_W, w), (mm.BLIT_H, h), (mm.BLIT_X0, x), (mm.BLIT_Y0, y)):
            self.w(16, off, v, 0.97)
        w, h = self.get(mm.BLIT_W), self.get(mm.BLIT_H)
        self.source(mm.BLIT_A_BASE, mm.BLIT_A_STRIDE, absolute, w, h)
        self.source(mm.BLIT_B_BASE, mm.BLIT_B_STRIDE, absolute, w, h)
        x0, y0 = self.get(mm.BLIT_X0, 16, True), self.get(mm.BLIT_Y0, 16, True)
        self.boundary(x0, y0, x0 + w, y0 + h)
        if not absolute and r.random() < 0.5:  # a move over its own destination: DESC changes the result
            ds = self.get(mm.BLIT_D_STRIDE)
            self.w(32, mm.BLIT_B_BASE, self.get(mm.BLIT_D_BASE, 32) + y0 * ds + x0 + r.randint(-340, 340))
            self.w(16, mm.BLIT_B_STRIDE, ds)
        self.run()

    def poly_line(self) -> None:
        self.poly(LINE, 2)

    def poly_tri(self) -> None:
        self.poly(TRI, 3)

    def vertices(self, n: int) -> list[tuple[int, int]]:
        r = self.r
        pts = [self.xy() for _ in range(n)]
        kind = r.choice(["free", "free", "free", "collinear", "same", "flat"])
        if kind == "collinear" and n == 3:
            dx, dy = r.randint(-30, 30), r.randint(-30, 30)
            pts = [pts[0], (pts[0][0] + dx, pts[0][1] + dy), (pts[0][0] + 2 * dx, pts[0][1] + 2 * dy)]
        elif kind == "same":
            pts = [pts[0]] * n if r.random() < 0.5 else [pts[0], pts[0]] + pts[2:]
        elif kind == "flat":
            pts = [(x, pts[0][1]) for x, _ in pts]
        return pts

    def poly(self, cmd: int, n: int) -> None:
        r = self.r
        edge = cmd == LINE and r.random() < 0.3
        self.common(
            cmd, r.choice(MINTERMS), r.choice([0, mm.CON_CLIP_EN, mm.CON_CLIP_EN]), r.choice([0, mm.CON2_HALFTONE_EN])
        )
        pts = self.vertices(n)
        if edge:
            pts = self.along_clip()
        for k, (x, y) in enumerate(pts):
            self.w(16, mm.BLIT_X0 + 4 * k, x, 0.97)
            self.w(16, mm.BLIT_Y0 + 4 * k, y, 0.97)
        xs = [self.get(mm.BLIT_X0 + 4 * k, 16, True) for k in range(n)]
        ys = [self.get(mm.BLIT_Y0 + 4 * k, 16, True) for k in range(n)]
        self.boundary(min(xs), min(ys), max(xs) + 1, max(ys) + 1)
        self.run()

    def along_clip(self) -> list[tuple[int, int]]:
        """A line along (or one pixel off) an edge of an explicit clip rect."""
        r = self.r
        cx, cy, cw, ch = r.randint(0, 100), r.randint(0, 80), r.randint(1, 200), r.randint(1, 120)
        self.w(8, mm.BLIT_CON, mm.CON_CLIP_EN)
        self.w(32, mm.BLIT_CLIP_X, cx | (cy << 16))
        self.w(32, mm.BLIT_CLIP_W, cw | (ch << 16))
        k = r.randint(-1, 1)
        left, right, top, bottom = cx + k, cx + cw - 1 + k, cy + k, cy + ch - 1 + k
        a, b = r.choice([(left, right), (right, left)]), r.choice([top, bottom])
        return r.choice(
            [
                [(left, cy - 3), (left, cy + ch + 3)],
                [(right, cy - 3), (right, cy + ch + 3)],
                [(cx - 3, bottom), (cx + cw + 3, bottom)],
                [(a[0], b), (a[1], b)],
            ]
        )


def make_script(seed: int, n: int) -> Script:
    """n ops: the four ops in turn, minterms cycled so every class meets every op."""
    s = RandomScript(seed)
    ops = [s.blit, s.fill, s.poly_line, s.poly_tri]
    for i in range(n):
        if i % 50 == 49:
            s.lines.append(f"seed {seed + i}")  # fresh memory now and then
        if i % 40 == 7:
            s.cmd = s.r.choice([0, 5, 9, 255])  # NOP and unknown commands: no draw, CYCLES kept / zero
            s.run()
        ops[i % 4]()
    return s
