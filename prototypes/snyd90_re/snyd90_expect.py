"""Expected shots for apps/snyd_90_headless.mjs: [window indices, physical RGB frame] SHA-256 prefixes.

intro      the Spectrum 512 picture (spu.py, pixel-checked against Hatari's capture).
menu-J     the menu after J iterations (menu_model.py, byte-checked against Hatari's RAM):
           the screen the J-th iteration drew.
The physical frame is 400x280: the 320x200 window at (40, 40), borders colour 0 (black here).
Colours as the port shows them: channel c * 255 // 7.
"""
import hashlib
import os
import struct

import menu_model as mm
import spu

MENU_SHOTS = (1, 2, 100, 531, 1000, 1200)


def color(w: int) -> bytes:
    return bytes(((w >> s) & 7) * 255 // 7 for s in (8, 4, 0))


def frame(idx: list[list[int]], regs: list[list[int]]) -> bytes:
    out = bytearray()
    for py in range(280):
        y = py - 40
        for px in range(400):
            x = px - 40
            if 0 <= y < 200 and 0 <= x < 320:
                out += color(regs[y][idx[y][x]])
            else:
                out += color(0)
    return bytes(out)


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()[:16]


def intro() -> tuple[str, str]:
    scr, pals = spu.load()
    idx, regs = [], []
    for y in range(200):
        row = [spu.pixel(scr, x, y) for x in range(320)]
        if y == 0:
            idx.append([0] * 320)
            regs.append([0] * 48)
            continue
        idx.append([spu.spu_index(x, c) for x, c in enumerate(row)])
        line = list(pals[y - 1])
        line[0] = pals[y - 2][32] if y >= 2 else 0
        regs.append(line)
    return sha(bytes(v for r in idx for v in r)), sha(frame(idx, regs))


def menu_shot(r: mm.Ram) -> tuple[str, str]:
    scr = r.l(0x3818)
    pal = [r.w(0x384C + 2 * i) for i in range(16)]
    idx = [[spu.pixel(r.m[scr:scr + 32000], x, y) for x in range(320)] for y in range(200)]
    return sha(bytes(v for row in idx for v in row)), sha(frame(idx, [pal] * 200))


def main() -> None:
    print(f'    "intro": {list(intro())},')
    r = mm.Ram()
    mm.init(r)
    done = 0
    for j in MENU_SHOTS:
        while done < j:
            mm.iteration(r)
            done += 1
        print(f'    "menu-{j:04d}": {list(menu_shot(r))},')


if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    main()
