"""RACER reference renderer (R82 M1): the Zig cart's frame in Python integers, from the track binary.

    python3 -I tools/racer/ref_render.py oval.ktrk --pose 3 [--r 5] [--no-decals] -o view.raw

Writes rows 12..187 of the 320-wide plane (176 x 320 bytes, palette indices) for fixed pose `k` (the
cart's keys A-H), CPU path, mulsh. apps/harness/racer_headless.mjs diffs it against the cart: pixel diff 0.
The pipeline is PORT_PLAN 1.5-1.8 as the cart does it; see apps/zig/scenes/racer/frame.zig for the stages.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ref_fx as fx  # noqa: E402
from racer.ref_fx import mulsh16  # noqa: E402
from racer.ref_sky import backdrop  # noqa: E402

Y0, Y1, CX16, CY16, F4 = 12, 188, 160 * 16, 100 * 16, 160 * 16
BACK, HEIGHT = (6 << 16, 3 << 16, 0), ((5 << 16) // 2, (3 << 16) // 2, (3 << 16) // 4)
PITCH = (0x06000000, 0x04000000, 0x01000000)
LAP = 720
SKY, GROUND = 1, 4


class Track:
    def __init__(self, blob: bytes) -> None:
        w = struct.unpack_from("<23I", blob)
        self.nv, nf, ni, nseg, ngrid = w[4:9]
        o = w[12:23] + (len(blob),)
        self.verts = [struct.unpack_from("<3h", blob, o[1] + 6 * i) for i in range(self.nv)]
        rec = lambda at, i: struct.unpack_from("<4HBBBB3hHiII", blob, at + 32 * i)  # noqa: E731
        self.faces = [rec(o[2], i) for i in range(nf)]
        self.inner = [rec(o[3], i) for i in range(ni)]
        first = struct.unpack_from("<1025I", blob, o[4])
        lists = struct.unpack_from(f"<{first[1024]}H", blob, o[5])
        self.tile_faces = [lists[first[t]:first[t + 1]] for t in range(1024)]
        self.index, self.pvs_at, self.blob = o[7], o[8], blob
        self.line = [struct.unpack_from("<3iHH", blob, o[9] + 16 * i) for i in range(nseg)]

    def baked(self, tile: int, bucket: int) -> list[int]:
        off = struct.unpack_from("<I", self.blob, self.index + 4 * (tile * 16 + bucket))[0]
        if off == 0xFFFFFFFF:
            raise ValueError("camera tile not baked: the reference has no DDA fallback")
        n = struct.unpack_from("<H", self.blob, self.pvs_at + 2 * off)[0]
        return list(struct.unpack_from(f"<{n}H", self.blob, self.pvs_at + 2 * off + 2))


def lap_pose(t: Track, frame: int, pov: int) -> tuple[list[int], int, int]:
    f = frame % LAP
    s = (f * len(t.line) << 16) // LAP
    i, fr = s >> 16, s & 0xFFFF
    a, b = t.line[i], t.line[(i + 1) % len(t.line)]
    dy = ((b[3] - a[3] + 0x8000) & 0xFFFF) - 0x8000
    yaw = ((a[3] + ((dy * fr) >> 16)) & 0xFFFF) << 16
    pos = [a[k] + mulsh16(b[k] - a[k], fr) for k in range(3)]
    pos[0] -= mulsh16(BACK[pov], fx.sin(yaw))
    pos[2] -= mulsh16(BACK[pov], fx.cos(yaw))
    pos[1] += HEIGHT[pov]
    return pos, yaw, PITCH[pov]


def view(pos: list[int], yaw: int, pitch: int) -> dict:
    sy, cy, sp, cp = fx.sin(yaw), fx.cos(yaw), fx.sin(pitch), fx.cos(pitch)
    r16 = [[cy, 0, -sy], [mulsh16(sy, sp), cp, mulsh16(cy, sp)], [mulsh16(sy, cp), -sp, mulsh16(cy, cp)]]
    tr = [-sum(mulsh16(row[j], pos[j]) for j in range(3)) for row in r16]
    tx, tz = min(max((pos[0] >> 19) + 16, 0), 31), min(max((pos[2] >> 19) + 16, 0), 31)
    tan = mulsh16(sp, fx.rcp(cp))
    return {"r": [[c << 9 for c in row] for row in r16], "t": tr, "eye": [c >> 9 for c in pos],
            "bucket": ((yaw + (1 << 27)) & fx.M32) >> 28, "tile": tz * 32 + tx,
            "hz": min(max(100 - ((tan * 160) >> 16), 0), 200)}


def project(v: list[int]) -> tuple[int, int]:
    inv = fx.rcp(v[2])
    return CX16 + mulsh16(mulsh16(v[0], inv), F4), CY16 - mulsh16(mulsh16(v[1], inv), F4)


def to_view(vw: dict, p: tuple[int, int, int]) -> list[int]:
    return [sum(mulsh16(vw["r"][i][j], p[j]) for j in range(3)) + vw["t"][i] for i in range(3)]


def reject(v: list[int]) -> int:
    x, y, z = v
    return (z < fx.NEAR) | (x < -z) << 1 | (x > z) << 2 | (20 * y + 11 * z < 0) << 3 | (11 * z - 20 * y < 0) << 4


def build(t: Track, vw: dict, f: tuple, cache: dict, key: int | None, out: list) -> int | None:
    nv = f[5]
    vs = [cache.setdefault(i, to_view(vw, t.verts[i])) for i in f[:nv]]
    allr = 0x1F
    for v in vs:
        allr &= reject(v)
    if allr:
        return None
    guard = 0
    for v in vs:
        guard |= fx.outside(v)
    poly = fx.clip([list(v) for v in vs], guard) if guard else vs
    if len(poly) < 3:
        return None
    pts = [project(v) for v in poly]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    if max(xs) < 0 or min(xs) >= 320 * 16 or max(ys) < Y0 * 16 or min(ys) >= Y1 * 16:
        return None
    zsum = sum(v[2] for v in vs)
    mean = zsum >> 2 if nv == 4 else mulsh16(zsum, 21845)
    k = key if key is not None else 1023 - min(max(mean >> 13, 0), 1023)
    out.append((k, f[6], xs, ys))
    return k


def collect(t: Track, vw: dict, r: int, decals: bool) -> list:
    out, cache, seen = [], {}, set()
    ents = t.baked(vw["tile"], vw["bucket"])
    for e in [e for e in ents if e >> 10 <= r]:
        for fid in t.tile_faces[e & 0x3FF]:
            if fid in seen:
                continue
            seen.add(fid)
            f = t.faces[fid]
            if not f[4] & 1 and sum(f[8 + k] * vw["eye"][k] for k in range(3)) <= f[12]:
                continue
            k = build(t, vw, (*f[0:4], f[4], f[5], f[6]), cache, None, out)
            if k is not None and decals:
                for d in t.inner[f[13]:f[13] + f[7]]:
                    build(t, vw, (*d[0:4], d[4], d[5], d[6]), cache, k, out)
    return out


def edge(px: int, py: int, qx: int, qy: int, y: int) -> list[int]:
    h, end = qy - py, (qy - 8 + 15) >> 4
    if h <= 0:
        return [px << 12, 0, end]
    slope = max(-(1 << 26), min(1 << 26, fx.i32(fx.tdiv((qx - px) << 12, h) << 4)))
    first = (py - 8 + 15) >> 4
    x = fx.i32((px << 12) + (slope >> 4) * ((first << 4) + 8 - py))
    if y > first:
        x = fx.i32(x + slope * (y - first))
    return [x, slope, end]


def fill_poly(img: bytearray, xs: list[int], ys: list[int], c: int) -> None:
    n = len(xs)
    top, bot = 0, 0
    for i, y in enumerate(ys):
        top, bot = (i if y < ys[top] else top), (i if y > ys[bot] else bot)
    ya, yc = max((ys[top] + 7) >> 4, Y0), min((ys[bot] + 7) >> 4, Y1)
    ia = ib = top
    a = b = [0, 0, ya]
    for y in range(ya, yc):
        while a[2] <= y:
            ja = (ia + 1) % n
            a, ia = edge(xs[ia], ys[ia], xs[ja], ys[ja], y), ja
        while b[2] <= y:
            jb = (ib + n - 1) % n
            b, ib = edge(xs[ib], ys[ib], xs[jb], ys[jb], y), jb
        lo, hi = min(a[0], b[0]), max(a[0], b[0])
        x0, x1 = max(fx.i32(lo + 0x7FFF) >> 16, 0), min(fx.i32(hi + 0x7FFF) >> 16, 320)
        if x1 > x0:
            img[y * 320 + x0:y * 320 + x1] = bytes([c]) * (x1 - x0)
        a[0], b[0] = fx.i32(a[0] + a[1]), fx.i32(b[0] + b[1])


def render(t: Track, pos: list[int], yaw: int, pitch: int, r: int = 5, decals: bool = True) -> bytes:
    vw = view(pos, yaw, pitch)
    img = bytearray(320 * 200)
    for y in range(Y0, Y1):
        img[y * 320:(y + 1) * 320] = bytes([SKY if y < vw["hz"] else GROUND]) * 320
    backdrop(img, yaw, vw["hz"], Y0)
    polys = collect(t, vw, r, decals)
    for _, c, xs, ys in sorted(polys, key=lambda p: p[0]):
        fill_poly(img, xs, ys, c)
    return bytes(img[Y0 * 320:Y1 * 320])


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("track")
    ap.add_argument("--pose", type=int, required=True)
    ap.add_argument("--r", type=int, default=5)
    ap.add_argument("--no-decals", action="store_true")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args(argv)
    t = Track(Path(a.track).read_bytes())
    pos, yaw, pitch = lap_pose(t, a.pose * (LAP // 8), a.pose % 3)
    Path(a.out).write_bytes(render(t, pos, yaw, pitch, a.r, not a.no_decals))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
