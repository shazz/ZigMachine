"""The car converter's checks (R82 M5 step 3): a `.kcar.json` document against limits.py, one message per refusal.

Each message names its limit and whether it is HARD (the cart cannot draw it: the face record, the one shadow quad) or SOFT
(over our frame budget or the size envelope: `carc.py --allow-soft` takes it anyway). The Blender panel shows `rows`.
"""

from __future__ import annotations

from racer import limits
from racer.kcar_export import PARTS, area2
from racer.ktrk import Doc, Vec, cross, dot, sub, unit

MATERIALS = ("body", "stripe", "dark", "glass", "rim", "head", "tail", "shadow")
REQUIRED = ("hull", "shadow", "lod1")
LOD0 = ("wheels", "hull", "cabin", "wing")
PLANAR_EPS = 0.5  # Q7: how far the 4th vertex of a quad may sit off the plane of the first three


def _pts(doc: Doc, ids: list[int]) -> list[Vec]:
    return [tuple(float(c) for c in doc["vertices"][i]) for i in ids]  # type: ignore[misc]  # [misc] 3 ints by schema


def lod0(doc: Doc) -> tuple[int, int]:
    """(faces, vertices used) of the near model."""
    faces = [f for p in LOD0 for f in doc["parts"].get(p, [])]
    return len(faces), len({i for f in faces for i in f["v"]})


def rows(doc: Doc) -> list[tuple[str, int, int, bool]]:
    """(label, value, limit, hard) per meter line, in the panel's order."""
    nf, nv = lod0(doc)
    return [("near faces", nf, limits.CAR_FACES, False), ("near vertices", nv, limits.CAR_VERTICES, False),
            ("far faces", len(doc["parts"].get("lod1", [])), limits.CAR_LOD1_FACES, False),
            ("vertices", len(doc["vertices"]), limits.CAR_MAX_VERTICES, True)]


def _convex(p: list[Vec], n: Vec) -> bool:
    turns = [dot(cross(sub(p[(i + 1) % 4], p[i]), sub(p[(i + 2) % 4], p[(i + 1) % 4])), n) for i in range(4)]
    return all(t > 0 for t in turns) or all(t < 0 for t in turns)


def _face(doc: Doc, where: str, f: Doc) -> list[str]:
    ids = f["v"]
    if f["mat"] not in MATERIALS:
        return [f"HARD limit: {where}: material {f['mat']!r} is not a car material ({', '.join(MATERIALS)})"]
    if not 3 <= len(ids) <= 4:
        return [f"HARD limit: {where} has {len(ids)} vertices (a face record holds 3 or 4)"]
    if any(not 0 <= i < len(doc["vertices"]) for i in ids):
        return [f"HARD limit: {where}: a vertex id is past the {len(doc['vertices'])} vertices"]
    p = _pts(doc, ids)
    if len(set(ids)) < len(ids) or area2(p) < 1e-6:
        return [f"HARD limit: {where} has no area (no normal)"]
    if len(ids) == 4:
        n = unit(cross(sub(p[1], p[0]), sub(p[2], p[0])))
        if area2(p[:3]) < 1e-6 or abs(dot(sub(p[3], p[0]), n)) > PLANAR_EPS:
            return [f"HARD limit: {where} is not planar (the 4th vertex is off the others' plane)"]
        if not _convex(p, n):
            return [f"HARD limit: {where} is not convex (the fill draws convex polygons)"]
    return []


def _shadow(doc: Doc) -> list[str]:
    fs = doc["parts"].get("shadow", [])
    if len(fs) != 1 or len(fs[0]["v"]) != 4 or fs[0]["mat"] != "shadow":
        return ["HARD limit: the shadow part must be exactly one quad of material shadow (the cart darkens one quad a car)"]
    lo, hi = limits.CAR_SHADOW_Y
    if any(not lo <= doc["vertices"][i][1] <= hi for i in fs[0]["v"]):
        return [f"HARD limit: the shadow quad must lie flat on the ground (y {lo}..{hi} Q7)"]
    return [f"HARD limit: material shadow is only for the shadow part ({p})" for p in PARTS if p != "shadow"
            for f in doc["parts"].get(p, []) if f["mat"] == "shadow"][:1]


def _envelope(doc: Doc) -> list[str]:
    for axis, (lo, hi) in enumerate(limits.CAR_ENVELOPE):
        cs = [v[axis] for v in doc["vertices"]]
        if cs and (min(cs) < lo or max(cs) > hi):
            return [f"SOFT limit: the car is {min(cs)}..{max(cs)} on {'xyz'[axis]}, the envelope is {lo}..{hi} (Q7)"]
    return []


def problems(doc: Doc) -> list[str]:
    out = [f"HARD limit: part {p} is missing (the cart draws {', '.join(REQUIRED)})" for p in REQUIRED if not doc["parts"].get(p)]
    for part, faces in doc["parts"].items():
        if part not in PARTS:
            out.append(f"HARD limit: no car part {part!r}")
        for fi, f in enumerate(faces):
            out += _face(doc, f"{part} face {fi}", f)
    if out:
        return out
    out += _shadow(doc)
    out += [f"{'HARD' if hard else 'SOFT'} limit: {label} {v} > {lim}" for label, v, lim, hard in rows(doc) if v > lim]
    return out + _envelope(doc)
