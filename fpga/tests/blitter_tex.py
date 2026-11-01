"""Randomised CHISEL v2 texture ops (AFFINE, MAP) in the blitter script format, mixed with the
v1 ops so stale registers cross between them. Span lists and maps are written to cart RAM
with `m` lines (linear-address memory writes); textures sit in cart RAM (SRC_ABS) or in the
video region, sometimes over the destination itself, so the RTL's read order matters."""

from blitter_random import RandomScript
from blitter_scripts import MINTERMS, PLANE, Script, mm

AFFINE, MAP = mm.BLIT_CMD_AFFINE, mm.BLIT_CMD_MAP
LIST_AT = 0x200000  # cart RAM: span lists
MAP_AT = 0x240000  # cart RAM: maps
SPAN = mm.BLIT_SPAN_BYTES


class TexScript(RandomScript):
    def texture(self) -> bool:
        """A_BASE/A_STRIDE/U_MASK/V_MASK; True when the texture is absolute (SRC_ABS)."""
        r = self.r
        um = r.choice([63, 127, 255, 31, 99, 0, 7, 319])
        vm = r.choice([63, 127, 255, 31, 57, 0, 3, 199])
        stride = r.choice([um + 1, 256, 320, 128, um + 1 + r.randint(0, 40)])
        absolute = r.random() < 0.6
        need = vm * stride + um + 1
        if absolute:
            base = r.choice([0x120000, 0x1C0000, 0x500000 + r.randrange(0, 0x100000), mm.CART_RAM_TOP - need])
            if r.random() < 0.07:  # past the window's end: refused
                base = mm.CART_RAM_TOP - need + r.randint(1, 8)
        else:  # in the video region: a plane, maybe the destination's own
            base = r.choice([PLANE, PLANE + 64000, self.get(mm.BLIT_D_BASE, 32), PLANE + r.randrange(0, 200000)])
        self.w(32, mm.BLIT_A_BASE, base, 0.97)
        self.w(16, mm.BLIT_A_STRIDE, stride, 0.97)
        self.w(16, mm.BLIT_U_MASK, um, 0.95)
        self.w(16, mm.BLIT_V_MASK, vm, 0.95)
        return absolute

    def tex_common(self, cmd: int) -> None:
        r = self.r
        con = r.choice([0, mm.CON_CLIP_EN, mm.CON_CLIP_EN]) | r.choice([0, 0, mm.CON_KEY_EN])
        mt = r.choice([mm.MT_B] * 4 + MINTERMS)
        self.common(cmd, mt, con, 0)
        absolute = self.texture()
        con2 = (mm.CON2_SRC_ABS if absolute else 0) | r.choice([0, 0, mm.CON2_TEX_CLIP])
        self.w(8, mm.BLIT_CON2, con2)

    def span_value(self) -> tuple[int, int]:
        r = self.r
        start = r.choice([r.randrange(1 << 32), r.randrange(0, 256 << 16), 0, (1 << 32) - (3 << 16)])
        step = r.choice([1 << 16, -(1 << 16), r.randint(-3 << 16, 3 << 16), r.randint(-300, 300), 0, r.randrange(1 << 32)])
        return start & 0xFFFFFFFF, step & 0xFFFFFFFF

    def affine(self) -> None:
        r = self.r
        self.tex_common(AFFINE)
        n = r.choice([1, 2, 5, 12, 30, 0, 200])
        at = LIST_AT + r.randrange(0, 0x1000, 4) + (2 if r.random() < 0.04 else 0)  # misaligned: refused
        if r.random() < 0.05:  # a list that runs off cart RAM: refused
            at = mm.CART_RAM_TOP - SPAN * max(n, 1) + 4
        ds = self.get(mm.BLIT_D_STRIDE) or 320
        y = r.randint(-5, 210)
        for k in range(min(n, 64)):  # the rest of a long list is whatever memory holds
            x0 = self.coord(-80, ds)
            x1 = x0 + r.choice([r.randint(0, 40), r.randint(-3, 0), r.randint(0, ds + 60)])
            if r.random() < 0.3:  # overlapping spans on one row: a pixel written twice
                y = y
            else:
                y = r.choice([y + 1, self.coord(-10, 280 if ds == 400 else 200)])
            (u0, du), (v0, dv) = self.span_value(), self.span_value()
            span = at + SPAN * k
            self.lines += [f"m16 {span:#x} {x0 & 0xFFFF:#x}", f"m16 {span + 2:#x} {x1 & 0xFFFF:#x}"]
            self.lines += [f"m16 {span + 4:#x} {y & 0xFFFF:#x}", f"m16 {span + 6:#x} 0"]
            for i, v in enumerate((u0, v0, du, dv)):
                self.lines.append(f"m32 {span + 8 + 4 * i:#x} {v:#x}")
        self.w(32, mm.BLIT_SPAN_BASE, at, 0.97)
        self.w(16, mm.BLIT_SPAN_COUNT, n, 0.97)
        self.run()

    def map_(self) -> None:
        r = self.r
        self.tex_common(MAP)
        (w, h), (x, y) = self.size(), self.xy()
        for off, v in ((mm.BLIT_W, w), (mm.BLIT_H, h), (mm.BLIT_X0, x), (mm.BLIT_Y0, y)):
            self.w(16, off, v, 0.97)
        w = self.get(mm.BLIT_W)
        stride = r.choice([2 * w, 2 * w, 2 * w + 2 * r.randint(0, 30), 640, 512] * 4 + [2 * w + 1])  # odd: refused
        at = MAP_AT + r.randrange(0, 0x400, 2) + (1 if r.random() < 0.04 else 0)
        if r.random() < 0.05:  # a map straddling the window's end: refused
            at = mm.CART_RAM_TOP - stride * max(self.get(mm.BLIT_H) - 1, 0) - 2 * w + 2
        if r.random() < 0.3:  # a map of small (u, v): the texture's corner, wrapped by the masks
            for k in range(0, 2 * min(w, 40), 2):
                self.lines.append(f"m16 {at + k:#x} {r.randrange(1 << 16):#x}")
        self.w(32, mm.BLIT_B_BASE, at, 0.97)
        self.w(16, mm.BLIT_B_STRIDE, stride, 0.97)
        self.w(16, mm.BLIT_U_OFF, r.randrange(1 << 16), 0.9)
        self.w(16, mm.BLIT_V_OFF, r.randrange(1 << 16), 0.9)
        self.run()


def make_tex_script(seed: int, n: int) -> Script:
    """n ops: AFFINE and MAP twice as often as each v1 op."""
    s = TexScript(seed)
    ops = [s.affine, s.map_, s.blit, s.affine, s.map_, s.fill, s.poly_line, s.poly_tri]
    for i in range(n):
        if i % 50 == 49:
            s.lines.append(f"seed {seed + i}")
        ops[i % len(ops)]()
    return s
