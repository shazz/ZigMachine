"""SNYD 90 menu (part 0 at $1000) as a RAM model, checked against Hatari dumps.

Run: python3 menu_model.py  -> compares screens + variables at iterations 0, 99, 530, 999.
The generated sprite code ($10C2) is replaced by the masked blit it compiles to: a pixel whose
four plane bits are all 0 is transparent; x is rounded down to even (8 preshifts of 2 px).
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
SCR_A, SCR_B = 0x6D800, 0x78000
WALKERS = (0x2F68, 0x2F86, 0x2FA4, 0x2FC2)


class Ram:
    def __init__(self) -> None:
        self.m = bytearray(0x100000)
        part = open(os.path.join(HERE, 'parts', 'p0_001000.bin'), 'rb').read()
        self.m[0x1000:0x1000 + len(part)] = part

    def w(self, a): return struct.unpack('>H', self.m[a:a + 2])[0]
    def l(self, a): return struct.unpack('>I', self.m[a:a + 4])[0]
    def sw(self, a, v): self.m[a:a + 2] = struct.pack('>H', v & 0xFFFF)
    def sl(self, a, v): self.m[a:a + 4] = struct.pack('>I', v & 0xFFFFFFFF)


SPRITES = []  # (src, columns) for the 11 bitmaps, from the generator's list at $386C


def init(r: Ram) -> None:
    for i in range(11):
        src, flag = r.l(0x386C + 8 * i), r.l(0x3870 + 8 * i)
        SPRITES.append((src, 3 if flag else 4))
        for sh in range(8):  # the generator's table entries: here, (sprite, shift) ids
            r.sl(0x1402 + 32 * i + 4 * sh, (i << 8) | sh)
    for wk in WALKERS:
        walk(r, wk)
    r.m[0x6D800:0x80000] = bytes(0x80000 - 0x6D800)


def walk(r: Ram, a: int) -> int:
    cur = r.l(a)
    v = r.w(cur + 2)
    cur += 2 * r.w(a + 0x10)
    if cur == r.l(a + 4):
        cur = r.l(a + 8)
        r.sw(a + 0xC, r.w(a + 0xC) - 1)
        if r.w(a + 0xC) == 0:
            p = r.l(a + 0x12)
            r.sw(a + 0xC, r.w(p))
            r.sw(a + 0x10, r.w(p + 2))
            p += 4
            if p == r.l(a + 0x16):
                p = r.l(a + 0x1A)
            r.sl(a + 0x12, p)
    r.sl(a, cur)
    return v


def amp(r: Ram, a: int) -> int:
    return (((walk(r, a) + 0x8000) & 0xFFFF) * r.w(a + 0xE)) >> 16


def phases(r: Ram) -> None:
    if r.w(0x29DE):
        r.sw(0x29DE, r.w(0x29DE) - 1)
        if r.w(0x29DE) == 0:
            a, b, c = r.l(0x29CC), r.l(0x29D0), r.l(0x29D4)
            r.sl(0x29CC, b), r.sl(0x29D0, c), r.sl(0x29D4, a), r.sl(0x158E, b)
        return
    st = r.w(0x29DA)
    if st:
        d = 1 if st == 2 else -1
        r.sw(0x29DC, r.w(0x29DC) + 160 * d)
        r.sw(0x2F76, r.w(0x2F76) + d), r.sw(0x2F94, r.w(0x2F94) + d)
        if st == 1 and r.w(0x29DC) == 0xD800:
            r.sw(0x2F76, 0), r.sw(0x2F94, 0), r.sw(0x29DA, 2), r.sw(0x29DE, 100)
        if not (st == 2 and r.w(0x29DC) == 0):
            return
        r.sw(0x2F76, 0x44), r.sw(0x2F94, 0x44), r.sw(0x29DA, 0)  # then idles this iteration too
    r.sw(0x29CA, r.w(0x29CA) - 1)
    if r.w(0x29CA) == 0:
        r.sw(0x29DA, 1), r.sw(0x29CA, 500)


def screen_select(r: Ram) -> int:
    r.sw(0x29D8, r.w(0x29D8) - 1)
    if r.w(0x29D8) == 0:
        r.sw(0x29D8, 2)
        scr = SCR_A
    else:
        scr = SCR_B
    r.sl(0x3818, scr)
    a, b = r.l(0x381C), r.l(0x3820)
    r.sl(0x381C, b), r.sl(0x3820, a)
    return scr


def clear(r: Ram, n: int) -> None:
    lst = r.l(0x381C)
    for k in range(n):
        a = r.l(lst + 4 * k)
        for row in range(62):
            o = (a + row * 160) & 0xFFFFFF
            r.m[o:o + 40] = bytes(40)


def scroller(r: Ram) -> None:
    sh = (r.w(0x1702) - 4) & 0xC
    r.sw(0x1702, sh)
    if sh == 0xC:
        col = (r.w(0x1704) + 8) % 0xA0
        r.sw(0x1704, col)
        r.sl(0x16FA, r.l(0x16F6))
        p = r.l(0x16FE)
        c = r.m[p]
        r.sl(0x16FE, p + 1)
        if c == 0xFF:
            c = r.m[0x1718]
            r.sl(0x16FE, 0x1719)
        r.sl(0x16F6, 0x19F2 if c == 0x20 else 0x1A5A + ((c - 0x41) & 0xFF) * 0x68)
    buf = r.l(0x1706 + sh) + r.w(0x1704)
    cur, prv = r.l(0x16F6), r.l(0x16FA)
    for row in range(13):
        for p in range(4):
            v = ((r.w(prv) << 16 | r.w(cur)) >> sh) & 0xFFFF  # ror.l: the low word
            prv, cur = prv + 2, cur + 2
            o = buf + row * 320 + 2 * p
            r.sw(o, v), r.sw(o + 160, v)
    src = buf + 8
    dst = r.l(0x3818) + 0x5780
    for row in range(13):
        r.m[dst:dst + 160] = r.m[src:src + 160]
        src, dst = src + 320, dst + 160


def blit(r: Ram, dst: int, sprite: int, sh: int) -> None:
    src, cols = SPRITES[sprite]
    for row in range(62):
        acc = [0, 0, 0, 0]
        for k in range(cols + 1):
            words = [r.w(src + (row * cols + k) * 8 + 2 * p) if k < cols else 0 for p in range(4)]
            out = []
            for p in range(4):
                full = (acc[p] << 16 | words[p]) >> sh
                out.append(full & 0xFFFF)
                acc[p] = words[p]
            m = out[0] | out[1] | out[2] | out[3]
            o = (dst + row * 160 + k * 8) & 0xFFFFFF
            for p in range(4):
                r.sw(o + 2 * p, (r.w(o + 2 * p) & ~m) | out[p])


def sprites(r: Ram) -> None:
    y = amp(r, 0x2F68) + amp(r, 0x2F86)
    x = amp(r, 0x2FA4) + amp(r, 0x2FC2)
    pos = (y * 160 + (x & 0xFFF0) // 2) & 0xFFFF
    a6 = r.l(0x2D92)
    for o in (0, 0x64):
        r.sw(a6 + o, pos), r.sw(a6 + o + 2, (x & 0xE) * 2)
    a6 += 4
    if a6 == 0x2DFA:
        a6 = 0x2D96
    r.sl(0x2D92, a6)
    n, lst, tabs = r.w(0x158C), r.l(0x381C), r.l(0x1592)
    for k in range(n):
        a5 = (r.l(0x3818) + r.w(a6) + (r.w(0x29DC) - 0x10000 if r.w(0x29DC) & 0x8000 else r.w(0x29DC))) & 0xFFFFFFFF
        r.sl(lst + 4 * k, a5)
        ident = r.l(r.l(tabs + 4 * k) + r.w(a6 + 2))
        blit(r, a5, ident >> 8, (ident & 7) * 2)
        a6 += 24


def iteration(r: Ram) -> None:
    phases(r)
    screen_select(r)
    s = r.l(0x158E)
    r.sw(0x158C, r.w(s))
    r.sl(0x1592, s + 2)
    clear(r, r.w(0x158C))
    scroller(r)
    sprites(r)


def check(r: Ram, name: str) -> bool:
    h = open(os.path.join(HERE, 'hatari', name), 'rb').read()
    ok = True
    for a, n, what in ((SCR_A, 32000, 'screen A'), (SCR_B, 32000, 'screen B'), (0x29CA, 22, 'phases'),
                       (0x2F68, 0x78, 'walkers'), (0x2D92, 0x6C, 'ring'), (0x16F6, 0x22, 'scroll vars'),
                       (0x38C4, 0x4100, 'scroll bufs'), (0x3818, 0x34, 'lists')):
        if r.m[a:a + n] != h[a:a + n]:
            bad = [i for i in range(n) if r.m[a + i] != h[a + i]]
            print(f'  {name}: {what} differs at {len(bad)} bytes, first ${a + bad[0]:x}')
            ok = False
    return ok


def main() -> None:
    r = Ram()
    init(r)
    done = 0
    for it, name in ((0, 'menu_it0.bin'), (99, 'menu_it99.bin'), (530, 'menu_it530.bin'), (999, 'menu_it999.bin')):
        while done < it:
            iteration(r)
            done += 1
        print(name, 'MATCH' if check(r, name) else 'DIFF')


if __name__ == '__main__':
    main()
