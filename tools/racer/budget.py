"""Track Kit budget check (R82 M5, PORT_PLAN 3.4): a `.ktrk.json` document's counts against limits.py.

`meter(doc)` gives the numbers (the Blender panel shows them); `problems(doc)` the refusals, each naming the limit and
whether it is HARD (the cart cannot hold it) or SOFT (over our frame budget). The priced-frame walk is walk.py.
"""

from __future__ import annotations

from dataclasses import dataclass

from racer import ktrk, limits
from racer.ktrk import Doc


@dataclass(frozen=True)
class Meter:
    vertices: int
    faces: int  # top-level faces + inner faces (decals): every one is drawn
    busiest_tile: int  # faces (+ their decals) binned on the fullest tile
    busiest_at: tuple[int, int]
    ramps: int  # track materials (each takes a palette ramp)
    segments: int


def meter(doc: Doc) -> Meter:
    per = ktrk.tile_faces(doc)
    weight = [1 + len(f.get("inner", [])) for f in doc["faces"]]
    loads = {t: sum(weight[i] for i in ids) for t, ids in per.items()}
    at = max(loads, key=lambda t: (loads[t], t)) if loads else (0, 0)
    mats = {f["mat"] for f in doc["faces"]} | {i["mat"] for f in doc["faces"] for i in f.get("inner", [])}
    if "palette" in doc:  # an authored track: kit.ramps gives every palette entry a ramp, the far ground included
        mats = set(doc["palette"]) | {doc.get("far_ground", "")} - {""}
    return Meter(len(doc["vertices"]), sum(weight), loads.get(at, 0), at, len(mats - set(limits.CAR_RAMPS)),
                 len(doc["racing_line"]))


def rows(m: Meter) -> list[tuple[str, int, int, bool]]:
    """(label, value, limit, hard) per line of the meter, in the panel's order."""
    return [
        ("faces in the busiest tile", m.busiest_tile, limits.TILE_FACES, False),
        ("faces (with decals)", m.faces, limits.TRACK_FACES, False),
        ("vertices", m.vertices, limits.TRACK_VERTICES, False),
        ("colour ramps", m.ramps, len(limits.FREE_RAMPS), True),
        ("racing-line segments", m.segments, limits.MAX_SEGMENTS, True),
    ]


def problems(doc: Doc) -> list[str]:
    m = meter(doc)
    out = [f"{'HARD' if hard else 'SOFT'} limit: {label} {value} > {limit}"
           + (f" (tile {m.busiest_at[0]},{m.busiest_at[1]})" if label.startswith("faces in") else "")
           for label, value, limit, hard in rows(m) if value > limit]
    if len(doc["start_grid"]) != limits.GRID_SLOTS:
        out.append(f"HARD limit: start grid has {len(doc['start_grid'])} slots, the race needs {limits.GRID_SLOTS}")
    cps = doc["checkpoints"]
    if cps != sorted(set(cps)):
        out.append(f"HARD limit: checkpoints {cps} must ascend strictly (the cart refuses the track at init)")
    for fi, f in enumerate(doc["faces"]):
        for k, face in enumerate([f, *f.get("inner", [])]):
            if _area2(ktrk.pts(doc, face["v"])) < 1e-6:
                out.append(f"HARD limit: face {fi}{f' inner {k - 1}' if k else ''} has no area (no normal)")
    return out


def _area2(p: list[ktrk.Vec]) -> float:
    total = (0.0, 0.0, 0.0)
    for i in range(1, len(p) - 1):
        c = ktrk.cross(ktrk.sub(p[i], p[0]), ktrk.sub(p[i + 1], p[0]))
        total = (total[0] + c[0], total[1] + c[1], total[2] + c[2])
    return ktrk.dot(total, total)
