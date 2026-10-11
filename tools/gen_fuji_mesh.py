#!/usr/bin/env python3
"""Trace the Atari Fuji out of a logo PNG and write the extruded solid as Zig.

    python3 tools/gen_fuji_mesh.py [--points 76] [--shot out.png]

Source: Atari-Logo.png from URL below (3840x2160, 1-bit palette, ink = index 1),
downloaded on first use into prototypes/fuji_logo/ (git-ignored: the PNG is not
ours to commit). Steps, all stdlib + PIL:
  1. ink mask (palette index 1), cropped to the first block of inked rows: the
     Fuji symbol, above the ATARI wordmark;
  2. downsampled with a box filter, so edges carry coverage (anti-aliasing);
  3. marching squares at 50 % coverage -> one closed loop per prong;
  4. Douglas-Peucker, epsilon searched so the three loops total ~--points;
  5. scaled to model units (x right, y DOWN, width -WIDTH..WIDTH, centred);
  6. ear clipping for the caps; one side quad (2 triangles) per outline edge;
  7. apps/zig/scenes/fuji_hobbytronic/mesh.zig: vertices, triangles, Q14
     outward normals, the face kind (front / back / side).
"""
import argparse
import math
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "prototypes/fuji_logo/Atari-Logo.png"
OUT = ROOT / "apps/zig/scenes/fuji_hobbytronic/mesh.zig"
URL = "https://logos-world.net/wp-content/uploads/2021/08/Atari-Logo.png"
GRID_H = 320  # rows of the coverage grid the contours are traced on
WIDTH = 110  # model half-width
DEPTH = 14  # half the extrusion
MIN_EDGE = 3  # model units: shorter outline edges are merged after rounding


def fetch():
    """The source PNG, downloaded once; a failed or partial download leaves no file."""
    if SRC.exists():
        return
    SRC.parent.mkdir(parents=True, exist_ok=True)
    tmp = SRC.with_suffix(".part")
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310 -- a fixed https URL
        tmp.write_bytes(r.read())
    Image.open(tmp).verify()  # not an HTML error page
    tmp.replace(SRC)


def symbol_mask():
    fetch()
    im = Image.open(SRC)
    w, h = im.size
    px = im.load()
    rows = [any(px[x, y] == 1 for x in range(0, w, 2)) for y in range(h)]
    top = rows.index(True)
    bot = top
    while bot < h and rows[bot]:
        bot += 1  # the first empty row ends the symbol; the wordmark is below
    cols = [x for x in range(w) if any(px[x, y] == 1 for y in range(top, bot, 2))]
    box = (cols[0], top, cols[-1] + 1, bot)
    ink = im.crop(box).point(lambda v: 255 if v == 1 else 0, "L")
    return ink


def coverage(ink):
    f = ink.height / GRID_H
    small = ink.resize((round(ink.width / f), GRID_H), Image.BOX)
    w, h = small.size
    g = [[0.0] * (w + 2) for _ in range(h + 2)]  # a zero border closes every loop
    for y in range(h):
        for x in range(w):
            g[y + 1][x + 1] = small.getpixel((x, y)) / 255.0
    return g


def marching_squares(g, iso=0.5):
    h, w = len(g), len(g[0])
    pos = {}
    nxt = {}

    def edge(kind, x, y):
        key = (kind, x, y)
        if key not in pos:
            if kind == "h":  # (x,y)-(x+1,y)
                a, b = g[y][x], g[y][x + 1]
                pos[key] = (x + ((iso - a) / (b - a) if b != a else 0.5), y)  # 0.5: an edge not crossed, never used
            else:  # (x,y)-(x,y+1)
                a, b = g[y][x], g[y + 1][x]
                pos[key] = (x, y + ((iso - a) / (b - a) if b != a else 0.5))
        return key

    for y in range(h - 1):
        for x in range(w - 1):
            tl, tr, br, bl = g[y][x], g[y][x + 1], g[y + 1][x + 1], g[y + 1][x]
            c = (tl > iso) << 3 | (tr > iso) << 2 | (br > iso) << 1 | (bl > iso)
            if c in (0, 15):
                continue
            T, R, B, L = edge("h", x, y), edge("v", x + 1, y), edge("h", x, y + 1), edge("v", x, y)
            # Segments oriented with the ink on the right (y down), so loops chain.
            segs = {1: [(B, L)], 2: [(R, B)], 3: [(R, L)], 4: [(T, R)], 6: [(T, B)], 7: [(T, L)],
                    8: [(L, T)], 9: [(B, T)], 11: [(R, T)], 12: [(L, R)], 13: [(B, R)], 14: [(L, B)]}
            if c in (5, 10):
                centre = (tl + tr + br + bl) / 4 > iso
                segs[5] = [(R, T), (L, B)] if centre else [(L, T), (R, B)]
                segs[10] = [(T, L), (B, R)] if centre else [(T, R), (B, L)]
            for a, b in segs[c]:
                nxt[a] = b
    loops = []
    while nxt:  # every edge point has exactly one successor: follow each loop round
        start = next(iter(nxt))
        loop, cur = [], start
        while True:
            loop.append(pos[cur])
            cur = nxt.pop(cur)
            if cur == start:
                break
        loops.append(loop)
    return [l for l in loops if len(l) > 20]


def dp(points, eps):
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1e-9
    best, idx = -1, 0
    for i in range(1, len(points) - 1):
        p = points[i]
        d = abs(dy * (p[0] - a[0]) - dx * (p[1] - a[1])) / n
        if d > best:
            best, idx = d, i
    if best <= eps:
        return [a, b]
    return dp(points[: idx + 1], eps)[:-1] + dp(points[idx:], eps)


def simplify_loop(loop, eps):
    far = max(range(len(loop)), key=lambda i: math.dist(loop[0], loop[i]))
    first = dp(loop[: far + 1], eps)
    second = dp(loop[far:] + [loop[0]], eps)
    return first[:-1] + second[:-1]


def area(poly):
    return sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))) / 2


def ear_clip(poly):
    idx = list(range(len(poly)))
    s = 1 if area(poly) > 0 else -1
    tris = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return s * cross(a, b, p) >= 0 and s * cross(b, c, p) >= 0 and s * cross(c, a, p) >= 0

    while len(idx) > 3:
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if s * cross(a, b, c) <= 0:
                continue  # reflex (or flat): not an ear
            if any(inside(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            raise SystemExit("ear clipping found no ear: the outline self-intersects")
    tris.append(tuple(idx))
    return tris


def to_model(loops):
    xs = [p[0] for l in loops for p in l]
    ys = [p[1] for l in loops for p in l]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = WIDTH / ((max(xs) - min(xs)) / 2)
    out = []
    for l in loops:
        pts = []
        for x, y in l:
            p = (round((x - cx) * k), round((y - cy) * k))
            if not pts or math.dist(p, pts[-1]) >= MIN_EDGE:
                pts.append(p)
        while math.dist(pts[0], pts[-1]) < MIN_EDGE:
            pts.pop()  # a sliver edge costs two side triangles and shows nothing
        out.append(pts)
    return out


def build(polys):
    verts, faces = [], []
    q14 = lambda v: round(v * 16384)
    for poly in polys:
        n = len(poly)
        base = len(verts)
        verts += [(x, y, -DEPTH) for x, y in poly] + [(x, y, DEPTH) for x, y in poly]
        for t in ear_clip(poly):
            faces.append(([base + i for i in t], (0, 0, -16384), "front"))
            faces.append(([base + n + i for i in t], (0, 0, 16384), "back"))
        s = 1 if area(poly) > 0 else -1  # y down: positive = clockwise on screen
        for i in range(n):
            j = (i + 1) % n
            dx, dy = s * (poly[j][0] - poly[i][0]), s * (poly[j][1] - poly[i][1])
            l = math.hypot(dx, dy)
            nrm = (q14(dy / l), q14(-dx / l), 0)
            q = [base + i, base + j, base + n + j, base + n + i]
            faces.append(([q[0], q[1], q[2]], nrm, "side"))
            faces.append(([q[0], q[2], q[3]], nrm, "side"))
    assert len(verts) <= 256, "vertex indices are u8"
    return verts, faces


def write_zig(verts, faces, polys):
    rows = lambda items, per: [" ".join(items[i:i + per]) for i in range(0, len(items), per)]
    v = rows([f".{{ {x}, {y}, {z} }}," for x, y, z in verts], 8)
    f = rows([f".{{ .v = .{{ {a}, {b}, {c} }}, .n = .{{ {n[0]}, {n[1]}, {n[2]} }}, .kind = .{k} }}," for (a, b, c), n, k in faces], 3)
    caps = sum(1 for _, _, k in faces if k == "front")
    src = f"""// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the Atari Fuji as a solid. GENERATED, do not edit by hand:
//   python3 tools/gen_fuji_mesh.py
// traced from the Fuji of {URL}
// (marching squares on the symbol's coverage, Douglas-Peucker to {sum(map(len, polys))} outline
// points: {", ".join(str(len(p)) for p in polys)} for the three prongs, ear-clipped caps), then extruded
// DEPTH units each way along z.
//
// Model units: x right, y DOWN (screen sense), z away from the viewer; the
// logo spans x -{WIDTH}..{WIDTH}. Every face is a TRIANGLE (a side quad is two, sharing
// its normal), so the renderer can sort per triangle; each carries its outward
// unit normal in Q14 (16384 = 1.0), and the renderer culls and lights by
// rotating normals, never by a winding rule.
// --------------------------------------------------------------------------
const std = @import("std");

pub const DEPTH = {DEPTH};
pub const Kind = enum(u8) {{ front, back, side }};
pub const Face = struct {{ v: [3]u8, n: [3]i16, kind: Kind }};

pub const NV = {len(verts)};
pub const NF = {len(faces)};
pub const CAP_TRIS = {caps}; // triangles in the front cap (and in the back one)

pub const Model = struct {{ verts: [NV][3]i16, faces: [NF]Face }};
pub const MODEL: Model = .{{
    .verts = .{{
{chr(10).join("        " + r for r in v)}
    }},
    .faces = .{{
{chr(10).join("        " + r for r in f)}
    }},
}};

test "every face's normal is a unit vector" {{
    for (MODEL.faces) |fc| {{
        const n = fc.n;
        const len2 = @as(i64, n[0]) * n[0] + @as(i64, n[1]) * n[1] + @as(i64, n[2]) * n[2];
        try std.testing.expect(@abs(len2 - 16384 * 16384) < 16384 * 8);
    }}
}}
"""
    OUT.write_text(src)


def shot(polys, path):
    im = Image.new("RGB", (480, 400), (0, 0, 40))
    d = ImageDraw.Draw(im)
    for poly in polys:
        for t in ear_clip(poly):
            d.polygon([(240 + poly[i][0] * 2, 200 + poly[i][1] * 2) for i in t], fill=(200, 120, 40), outline=(255, 255, 255))
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--points", type=int, default=76)
    ap.add_argument("--shot")
    a = ap.parse_args()
    loops = marching_squares(coverage(symbol_mask()))
    if len(loops) != 3:
        raise SystemExit(f"expected 3 prongs, traced {len(loops)} loops")
    loops.sort(key=lambda l: min(p[0] for p in l))  # left finger, bar, right finger
    lo, hi = 0.05, 20.0
    for _ in range(40):  # the smallest epsilon whose outlines fit the budget
        eps = (lo + hi) / 2
        if sum(len(simplify_loop(l, eps)) for l in loops) > a.points:
            lo = eps
        else:
            hi = eps
    polys = to_model([simplify_loop(l, hi) for l in loops])
    verts, faces = build(polys)
    write_zig(verts, faces, polys)
    if a.shot:
        shot(polys, a.shot)
    print(f"eps {hi:.2f} grid px; outline points {[len(p) for p in polys]}; {len(verts)} vertices, {len(faces)} triangles -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
