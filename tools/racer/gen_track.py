"""Procedural test track for Kestrel Racing (R82 M0): an oval with a crest, a banked turn, shoulders, walls
and decals, written as `.ktrk.json` (racer.ktrk). Deterministic: same arguments, same bytes. Original shape,
nothing taken from any game's data.

    python3 tools/racer/gen_track.py -o oval.ktrk.json [--segments 120]
    python3 tools/racer/gen_track.py --stress -o city.ktrk.json      # the dense "stress city" (gen_city.py)
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

if __package__ in (None, ""):  # run as a script: make `racer` importable
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ktrk  # noqa: E402
from racer.ktrk import Builder, Doc  # noqa: E402

A, B = 50.0, 90.0  # ellipse semi-axes: x, z (the start straight runs along +z at x = +A)
HALF, SHOULDER, WALL_H = 3.0, 2.0, 0.6
CREST_AT, CREST_H, CREST_W = 0.2 * math.pi, 2.5, 0.12 * math.pi
BANK_AT, BANK_S, BANK_W = 0.55 * math.pi, 0.14, 0.3 * math.pi
OFFSETS = (-(HALF + SHOULDER), -HALF, HALF, HALF + SHOULDER)


def _window(theta: float, centre: float, half: float) -> float:
    d = abs(theta - centre)
    return 0.5 * (1 + math.cos(math.pi * d / half)) if d < half else 0.0


def _arc_thetas(n: int) -> list[float]:
    """Ellipse angles of n points equally spaced in arc length, starting at theta = 0."""
    steps = 20000
    cum, last, total = [0.0], (A, 0.0), 0.0
    for k in range(1, steps + 1):
        th = 2 * math.pi * k / steps
        cur = (A * math.cos(th), B * math.sin(th))
        total += math.hypot(cur[0] - last[0], cur[1] - last[1])
        cum.append(total)
        last = cur
    out, k = [], 0
    for i in range(n):
        while cum[k + 1] < total * i / n:
            k += 1
        frac = (total * i / n - cum[k]) / (cum[k + 1] - cum[k])
        out.append(2 * math.pi * (k + frac) / steps)
    return out


def _station(theta: float) -> tuple[float, float, float, float, float, float]:
    """(x, z, right_x, right_z, y_centre, bank_sin) at an ellipse angle."""
    tx, tz = -A * math.sin(theta), B * math.cos(theta)
    n = math.hypot(tx, tz)
    y = CREST_H * _window(theta, CREST_AT, CREST_W)
    return A * math.cos(theta), B * math.sin(theta), tz / n, -tx / n, y, BANK_S * _window(theta, BANK_AT, BANK_W)


def _rows(b: Builder, st: tuple[float, ...]) -> tuple[list[int], list[int]]:
    x, z, rx, rz, y, s = st
    ground = [b.vert(x + o * rx, y + o * s, z + o * rz) for o in OFFSETS]
    top = [b.vert(x + o * rx, y + o * s + WALL_H, z + o * rz) for o in (OFFSETS[0], OFFSETS[3])]
    return ground, top


def _decals(b: Builder, road: Doc, corners: list[int], i: int) -> None:
    kerb = ("kerb_a", "kerb_b")[i % 2]
    b.decal(road, corners, (0.0, 1.0), (0.0, 0.07), kerb)
    b.decal(road, corners, (0.0, 1.0), (0.93, 1.0), kerb)
    if i % 2 == 0:
        b.decal(road, corners, (0.15, 0.85), (0.49, 0.51), "paint")
    if i == 0:
        b.decal(road, corners, (0.3, 0.6), (0.08, 0.92), "paint_start")


def _segment_faces(b: Builder, i: int, g0: list[int], g1: list[int], t0: list[int], t1: list[int]) -> None:
    b.face([g0[0], g0[1], g1[1], g1[0]], "ground", "grass", borders=[(g0[0], g1[0])])
    road = b.face([g0[1], g0[2], g1[2], g1[1]], "track", "asphalt")
    _decals(b, road, [g0[1], g0[2], g1[2], g1[1]], i)
    b.face([g0[2], g0[3], g1[3], g1[2]], "ground", "grass", borders=[(g0[3], g1[3])])
    b.face([g0[0], g1[0], t1[0], t0[0]], "wall", "wall", dual=True)
    b.face([g0[3], g1[3], t1[1], t0[1]], "wall", "wall", dual=True)


def _grid_entry(st: tuple[float, ...], seg: int, lateral: float) -> Doc:
    x, z, rx, rz, y, s = st
    yaw = (math.atan2(-rz, rx) / (2 * math.pi)) % 1.0  # forward = (-rz, rx); angle 0 = +z, grows toward +x
    return {"segment": seg, "pos": [ktrk.q(x + lateral * rx), ktrk.q(y + lateral * s), ktrk.q(z + lateral * rz)],
            "yaw_q16": int(round(yaw * 65536)) & 0xFFFF}


def build_oval(segments: int = 120) -> Doc:
    """The test oval as a ktrk-json document. `segments` >= 57 so seven AI cars can start at 8 * i."""
    if segments < 57:
        raise ValueError("segments must be at least 57")
    b = Builder()
    sts = [_station(t) for t in _arc_thetas(segments)]
    rows = [_rows(b, st) for st in sts]
    for i in range(segments):
        (g0, t0), (g1, t1) = rows[i], rows[(i + 1) % segments]
        _segment_faces(b, i, g0, g1, t0, t1)
    line = [{"l": g[1], "r": g[2]} for g, _ in rows]
    checkpoints = [segments * k // 4 - 1 for k in (1, 2, 3, 4)]
    grid = [_grid_entry(sts[8 * k], 8 * k, (0.0, 1.0, -1.0, 1.0)[k % 4]) for k in range(8)]
    meta = {"kind": "oval", "segments": segments, "ellipse": [A, B], "half_width": HALF}
    return b.document("test_oval", meta, line, checkpoints, grid)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", help="output file (default: stdout)")
    ap.add_argument("--segments", type=int, default=120)
    ap.add_argument("--stress", action="store_true", help="the dense stress city instead of the oval")
    args = ap.parse_args(argv)
    if args.stress:
        from racer import gen_city
        doc = gen_city.build_city()
    else:
        doc = build_oval(args.segments)
    text = ktrk.dumps(doc)
    if args.out:
        Path(args.out).write_text(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
