"""A float reference frame of mix3, to pin the conventions the cart's Q16 code copies.

  python3 -I tools/sb_mix3/preview.py <suicide-barbie checkout> <frame 0..480> <out.png> [transpose]

Row vectors (D3D style, the PSP's gum): p_world = p_local * R(q) + t, view = the
camera's world matrix inverted, the PSP's projection (fov 45, 16:9, looking down -z),
320x180 letterboxed in 320x200. Triangles are flat-coloured by the texel at their
centroid, culled by screen winding and painted far to near.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert  # noqa: E402
import read  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

F = 90.0 / math.tan(math.radians(22.5))  # pixels per unit at depth 1 (180 rows = fov 45)


def rot(qv, transpose):
    x, y, z, w = qv
    m = [[1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)],
         [2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)],
         [2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]]
    return [list(r) for r in zip(*m)] if transpose else m


def xf(p, m, t):
    return [p[0] * m[0][k] + p[1] * m[1][k] + p[2] * m[2][k] + t[k] for k in range(3)]


def render(src, frame, transpose=False):
    psp = os.path.join(src, 'ReleaseCandidate/__SCE__SuicideBarbie/BarbieData/mix/mix3/psp')
    sc = read.scene(os.path.join(psp, 'mix3.msk'))
    anim = read.anim(os.path.join(psp, 'mix3.man'))
    texs = {t[:-4]: read.texture(os.path.join(psp, t)) for t in sc['textures']}
    ct, cq, _ = anim['camera1'][frame]
    cm = rot(cq, transpose)
    inv = [list(r) for r in zip(*cm)]  # orthonormal: inverse rotation = transpose
    ci = [-sum(ct[j] * inv[j][k] for j in range(3)) for k in range(3)]
    polys, front = [], 0
    for it in convert.items(sc, psp):
        t, rq, _ = anim[it['node']][min(frame, len(anim[it['node']]) - 1)]
        m = rot(rq, transpose)
        mesh = it['mesh']
        vv = [xf(xf(p, m, t), inv, ci) for p in mesh['p']]
        tw, th, rows = texs[it['tex']]
        for a, b, c in mesh['tris']:
            ps = [vv[a], vv[b], vv[c]]
            if any(p[2] > -1.0 for p in ps):
                continue
            front += 1
            s = [(160 + F * p[0] / -p[2], 100 - F * p[1] / -p[2]) for p in ps]
            area = (s[1][0] - s[0][0]) * (s[2][1] - s[0][1]) - (s[2][0] - s[0][0]) * (s[1][1] - s[0][1])
            if area >= 0:
                continue
            uv = [sum(mesh['uv'][i][k] for i in (a, b, c)) / 3 for k in range(2)]
            if it['env']:
                nz = [xf(mesh['n'][i], m, (0, 0, 0)) for i in (a, b, c)]
                nv = [sum(xf(n, inv, (0, 0, 0))[k] for n in nz) / 3 for k in range(2)]
                uv = [(1 + nv[0]) / 2, (1 - nv[1]) / 2]
            col = rows[min(int(uv[1] * th), th - 1)][min(int(uv[0] * tw), tw - 1)]
            polys.append((sum(p[2] for p in ps), s, col[:3]))
    im = Image.new('RGB', (320, 200))
    d = ImageDraw.Draw(im)
    for _, s, col in sorted(polys, key=lambda x: x[0]):
        d.polygon(s, fill=col)
    d.rectangle((0, 0, 319, 9), fill=0)
    d.rectangle((0, 190, 319, 199), fill=0)
    return im, front, len(polys)


if __name__ == '__main__':
    img, n_front, n_drawn = render(sys.argv[1], int(sys.argv[2]), len(sys.argv) > 4)
    img.save(sys.argv[3])
    print('in front %d, drawn %d' % (n_front, n_drawn))
