"""LOCAL ONLY importer step (R82 32X look, item 3): the water's surface pattern, as alternating face tones.

The 32X's water is not one flat blue: its surface reads as a pattern of close tones. We match it the arcade's way,
with no per-pixel work and no dither of ours: every flat water face (a blue-dominant colour lying level) is 2-coloured
over its edge neighbours, and the second colour is the same ramp one level darker (one level lighter at a ramp's
bottom). Adjacent water faces then alternate, as the arcade's alternating panels do. Holds no data.
"""

from __future__ import annotations

from collections import deque

from racer import ktrk

ALT = 0x100  # a material "c1xx": palette entry xx's alternate tone
LEVEL_NY = 0.95  # water lies level
RGB = tuple[int, int, int]
At = dict[int, tuple[int, int]]


def is_water(rgb: RGB) -> bool:
    r, g, b = rgb
    return b >= 96 and b >= r + 48 and b >= g + 32


def _level(doc: ktrk.Doc, f: ktrk.Doc) -> bool:
    vs = doc["vertices"]
    p = [tuple(c / doc["vertex_scale"] for c in vs[i]) for i in f["v"]]
    return abs(ktrk.normal(p)[1]) >= LEVEL_NY  # either winding: a lake seen from above


def _edges(faces: list[ktrk.Doc], ids: list[int]) -> dict[int, list[int]]:
    at: dict[tuple[int, int], list[int]] = {}
    for i in ids:
        v = faces[i]["v"]
        for e in range(len(v)):
            a, b = v[e], v[(e + 1) % len(v)]
            at.setdefault((min(a, b), max(a, b)), []).append(i)
    nb: dict[int, list[int]] = {i: [] for i in ids}
    for fs in at.values():
        for i in fs:
            nb[i] += [j for j in fs if j != i]
    return nb


def alternate(doc: ktrk.Doc, pal: list[RGB], at: At) -> int:
    """2-colour the level water faces of `doc` (in place: materials "c1xx", `at` gains their shades); returns how many
    faces took the alternate tone."""
    faces = doc["faces"]
    ids = [i for i, f in enumerate(faces) if is_water(pal[int(f["mat"][1:], 16)]) and _level(doc, f)]
    nb, side, n = _edges(faces, ids), {}, 0
    for s in ids:
        if s in side:
            continue
        side[s], todo = 0, deque([s])
        while todo:
            i = todo.popleft()
            for j in nb[i]:
                if j not in side:
                    side[j] = 1 - side[i]
                    todo.append(j)
    for i, k in side.items():
        if k:
            c = int(faces[i]["mat"][1:], 16)
            ramp, lv = at[c]
            at[ALT | c] = (ramp, lv - 1 if lv > 0 else lv + 1)
            faces[i]["mat"] = f"c{ALT | c:03x}"
            n += 1
    doc["materials"] = sorted({f["mat"] for f in faces} | {i["mat"] for f in faces for i in f.get("inner", [])})
    return n
