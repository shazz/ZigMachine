"""The priced-frame walk of the Track Kit budget check (R82 M5, PORT_PLAN 3.4): the lap v0 flyby camera at every 3rd script
frame (its POV by thirds), the reference renderer's visibility and collection counted at each pose, priced with PORT_PLAN
2.3's LOW column (flat shading, mulsh, AFFINE pixels: the fill path M1 chose) plus FRESCO's one plane. ESTIMATES, not
re-fitted to the board yet. The heaviest poses (at least HEAVY_GAP frames apart) are what the harness pins against the cart.

    python3 -I tools/racer/walk.py apps/zig/assets/screens/racer/salt.ktrk [--r 5] [--top 5]
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import limits  # noqa: E402
from racer import ref_render as rr  # noqa: E402

COST = {"verts": 50, "faces": 120, "polys": 200, "spans": 35}  # cycles an item, PORT_PLAN 2.3 low column
FIXED_MC = 0.70 + 0.06  # FRESCO's enabled plane + frame base, and the cart's fixed share (HUD, physics, AI, calls)
STEP, HEAVY_GAP = 3, 24


@dataclass(frozen=True)
class Pose:
    frame: int
    verts: int
    faces: int
    polys: int
    spans: int
    pixels: int

    @property
    def mc(self) -> float:
        return FIXED_MC + sum(COST[k] * getattr(self, k) for k in COST) / 1e6


def _rows_area(xs: list[int], ys: list[int]) -> tuple[int, int]:
    rows = max(0, min((max(ys) + 7) >> 4, rr.Y1) - max((min(ys) + 7) >> 4, rr.Y0))
    area = abs(sum(xs[i] * ys[i - 1] - xs[i - 1] * ys[i] for i in range(len(xs)))) // 512
    return rows, min(area, 320 * (rr.Y1 - rr.Y0))


def count(t: rr.Track, frame: int, r: int) -> Pose:
    pos, yaw, pitch = rr.lap_pose(t, frame, rr.pov_at(frame))
    vw = rr.view(pos, yaw, pitch)
    ents = [e for e in t.baked(vw["tile"], vw["bucket"]) if e >> 10 <= r]
    fids = list(dict.fromkeys(f for e in ents for f in t.tile_faces[e & 0x3FF]))
    polys: list = []
    cache: dict = {}
    for fid in fids:
        f = t.faces[fid]
        if not f[4] & 1 and sum(f[8 + k] * vw["eye"][k] for k in range(3)) <= f[12]:
            continue
        k = rr.build(t, vw, (*f[0:4], f[4], f[5], f[6]), cache, None, polys)
        if k is not None:
            for d in t.inner[f[13]:f[13] + f[7]]:
                rr.build(t, vw, (*d[0:4], d[4], d[5], d[6]), cache, k, polys)
    ra = [_rows_area(xs, ys) for _, _, xs, ys in polys]
    return Pose(frame, len(cache), len(fids), len(polys), sum(a for a, _ in ra), sum(b for _, b in ra))


def walk(t: rr.Track, r: int = limits.BENCH_R) -> list[Pose]:
    return [count(t, f, r) for f in range(0, rr.LAP, STEP)]


def heaviest(poses: list[Pose], n: int = 5) -> list[Pose]:
    out: list[Pose] = []
    for p in sorted(poses, key=lambda p: (-p.mc, p.frame)):
        if all(min(abs(p.frame - q.frame), rr.LAP - abs(p.frame - q.frame)) >= HEAVY_GAP for q in out):
            out.append(p)
        if len(out) == n:
            break
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("track")
    ap.add_argument("--r", type=int, default=limits.BENCH_R)
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--write", help="write the heaviest frames as JSON (the racer_tracks harness and the tests read it)")
    a = ap.parse_args(argv)
    poses = walk(rr.Track(Path(a.track).read_bytes()), a.r)
    print(f"| frame | POV | verts | faces | polys | spans | pixels | est. Mc |  (R = {a.r}, {len(poses)} poses)\n|---|---|---|---|---|---|---|---|")
    for p in heaviest(poses, a.top):
        print(f"| {p.frame} | {rr.pov_at(p.frame)} | {p.verts} | {p.faces} | {p.polys} | {p.spans} | {p.pixels} | {p.mc:.2f} |")
    if a.write:
        Path(a.write).write_text(json.dumps({"r": a.r, "frames": [p.frame for p in heaviest(poses, a.top)]}) + "\n")
    worst = max(p.mc for p in poses)
    if worst > limits.FRAME_MC:
        print(f"walk: SOFT limit: the heaviest pose costs {worst:.2f} Mc > {limits.FRAME_MC}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
