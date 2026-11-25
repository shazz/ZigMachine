"""Track Kit export (R82 M5): a Blender scene's mesh data -> the `.ktrk.json` document. No `bpy` here, so it runs in the gate.

The add-on (tools/racer/blender/) reads the scene into a plain `Scene` dict (`extract`), this module turns it into the
document. Authoring conventions (freds72's, PORT_PLAN 3.5, rewritten for our format):
- vertex groups: TRACK_FACE (asphalt, drivable), GROUND_FACE (drivable off-road), DETAIL_FACE (a decal: drawn on the ground
  face under it), PROP_FACE (scenery); any other face is a wall. A face is in a group when ALL its vertices are, and the
  first of DETAIL, TRACK, GROUND, PROP that holds it wins.
- BORDER1..3 (any BORDER* group): an edge of a ground face whose two vertices are both in one is a wall edge for the physics.
- TRACK_L / TRACK_R: the racing line's left and right edge loops; LINE_START holds segment 0's L vertex; the walk goes the
  way slot 0 of the start grid faces. CHECKPT_1..n: one L vertex each, in lap order (the segment ending at it).
- objects parented to an object named `start_grid`: the 8 grid slots (sorted by name), facing their local +Y.
- materials: custom property `ktrk_rgb` = [r, g, b] (the palette colour), `ktrk_dual` = 1 for double-sided faces.
- scene custom properties: `ktrk_name`, `ktrk_mood`, `ktrk_sun` [x, y, z] (Blender axes), `ktrk_far_ground`.
Blender is Z-up, the engine y-up: (x, y, z) -> (x, z, y), a reflection, so a face wound counter-clockwise seen from outside
in Blender keeps its outward normal under the engine's (last - first) x (second - first). Every non-ground face is checked.
"""

from __future__ import annotations

import math
from typing import Any

from racer import ktrk
from racer.ktrk import Builder, Doc

Scene = dict[str, Any]  # WHY: the add-on's plain JSON-shaped extract (lists and dicts), described above
KINDS = (("DETAIL_FACE", "detail"), ("TRACK_FACE", "track"), ("GROUND_FACE", "ground"), ("PROP_FACE", "prop"))


class KitError(ValueError):
    """The scene breaks an authoring convention."""


def to_engine(v: list[float]) -> ktrk.Vec:
    return (v[0], v[2], v[1])


def _merge(sc: Scene) -> tuple[list[list[float]], list[Doc], set[tuple[int, int]], dict[str, set[int]]]:
    verts: list[list[float]] = []
    faces: list[Doc] = []
    edges: set[tuple[int, int]] = set()
    groups: dict[str, set[int]] = {}
    for ob in sc["objects"]:
        base = len(verts)
        verts += ob["verts"]
        faces += [{**f, "v": [base + i for i in f["v"]]} for f in ob["faces"]]
        edges |= {(base + min(a, b), base + max(a, b)) for a, b in ob["edges"]}
        for name, ids in ob["groups"].items():
            groups.setdefault(name, set()).update(base + i for i in ids)
    return verts, faces, edges, groups


def _kind(ids: list[int], groups: dict[str, set[int]]) -> str:
    for group, kind in KINDS:
        if all(i in groups.get(group, ()) for i in ids):
            return kind
    return "wall"


def _check_normal(fi: int, pts: list[ktrk.Vec], bnormal: list[float]) -> None:
    if ktrk.dot(ktrk.normal(pts), ktrk.unit(to_engine(bnormal))) < 0.5:
        raise KitError(f"face {fi}: the engine's normal disagrees with Blender's (winding)")


def _borders(ids: list[int], groups: dict[str, set[int]]) -> list[tuple[int, int]]:
    sets = [s for name, s in groups.items() if name.startswith("BORDER")]
    pairs = zip(ids, ids[1:] + ids[:1], strict=True)
    return [(a, b) for a, b in pairs if any(a in s and b in s for s in sets)]


def _faces(sc: Scene, b: Builder, verts: list[list[float]], faces: list[Doc], groups: dict[str, set[int]]) -> list[int]:
    bid = [b.vert(*to_engine(v)) for v in verts]
    mats = sc["materials"]
    decals = []
    for fi, f in enumerate(faces):
        if f["mat"] not in mats:
            raise KitError(f"face {fi}: material {f['mat']!r} has no ktrk_rgb")
        kind = _kind(f["v"], groups)
        ids = [bid[i] for i in f["v"]]
        if kind == "detail":
            decals.append((fi, ids, f["mat"]))
            continue
        if kind not in ktrk.GROUND_KINDS:
            _check_normal(fi, ktrk.pts({"vertices": b.vertices}, ids), f["normal"])
        borders = [(bid[x], bid[y]) for x, y in _borders(f["v"], groups)] if kind in ktrk.GROUND_KINDS else []
        b.face(ids, kind, f["mat"], borders=borders, dual=bool(mats[f["mat"]].get("dual")))
    for fi, ids, mat in decals:
        _attach(b, fi, ids, mat)
    return bid


def _attach(b: Builder, fi: int, ids: list[int], mat: str) -> None:
    doc = {"vertices": b.vertices}
    p = ktrk.pts(doc, ids)
    if ktrk.normal(p)[1] < 0:
        ids, p = ids[::-1], p[::-1]
    for parent in b.faces:
        if parent["kind"] not in ktrk.GROUND_KINDS:
            continue
        pp = ktrk.pts(doc, parent["v"])
        if all(ktrk.inside_by(pp, v, ktrk.DECAL_TOL) and abs(v[1] - ktrk.plane_y(pp, v[0], v[2])) <= ktrk.PLANAR_EPS for v in p):
            parent.setdefault("inner", []).append({"v": ids, "mat": mat})
            return
    raise KitError(f"face {fi}: a DETAIL_FACE lies on no ground face")


def _loop(group: set[int], edges: set[tuple[int, int]]) -> dict[int, list[int]]:
    adj: dict[int, list[int]] = {v: [] for v in group}
    for a, c in edges:
        if a in group and c in group:
            adj[a].append(c)
            adj[c].append(a)
    bad = [v for v, n in adj.items() if len(n) != 2]
    if bad:
        raise KitError(f"TRACK_L is not one closed edge loop ({len(bad)} vertices without exactly two neighbours)")
    return adj


def _walk(sc: Scene, verts: list[list[float]], edges: set[tuple[int, int]], groups: dict[str, set[int]]) -> tuple[list[int], list[int]]:
    left, right = groups.get("TRACK_L", set()), groups.get("TRACK_R", set())
    adj = _loop(left, edges)
    start = sorted(groups.get("LINE_START", set()) & left)
    if len(start) != 1 or not sc["grid"]:
        raise KitError("LINE_START must hold exactly one TRACK_L vertex, and the start grid must exist")
    rz = sc["grid"][0]["rot_z"]
    fwd = (-math.sin(rz), math.cos(rz))
    s = start[0]
    nxt = max(adj[s], key=lambda n: (verts[n][0] - verts[s][0]) * fwd[0] + (verts[n][1] - verts[s][1]) * fwd[1])
    ls, prev = [s], s
    while nxt != s:
        ls.append(nxt)
        prev, nxt = nxt, next(n for n in adj[nxt] if n != prev)
    rs = []
    for v in ls:
        rr = [c for a, c2 in edges for c in (a, c2) if v in (a, c2) and c != v and c in right]
        if len(rr) != 1:
            raise KitError(f"TRACK_L vertex {v}: {len(rr)} TRACK_R vertices joined to it by an edge, want 1")
        rs.append(rr[0])
    return ls, rs


def _checkpoints(ls: list[int], groups: dict[str, set[int]]) -> list[int]:
    names = sorted((g for g in groups if g.startswith("CHECKPT_")), key=lambda g: int(g.split("_")[1]))
    out = []
    for g in names:
        hit = [ls.index(v) for v in groups[g] if v in ls]
        if len(hit) != 1:
            raise KitError(f"{g} must hold exactly one TRACK_L vertex")
        out.append((hit[0] - 1) % len(ls))
    return out


def _grid(sc: Scene, b: Builder, line: list[dict[str, int]]) -> list[Doc]:
    vs = b.vertices
    centres = [((vs[s["l"]][0] + vs[s["r"]][0]) / 256, (vs[s["l"]][2] + vs[s["r"]][2]) / 256) for s in line]
    out = []
    for slot in sorted(sc["grid"], key=lambda g: g["name"]):
        x, y, z = to_engine(slot["pos"])
        seg = min(range(len(centres)), key=lambda i: math.hypot(centres[i][0] - x, centres[i][1] - z))
        fx, fz = -math.sin(slot["rot_z"]), math.cos(slot["rot_z"])
        yaw = (math.atan2(fx, fz) / (2 * math.pi)) % 1.0
        out.append({"segment": seg, "pos": [ktrk.q(x), ktrk.q(y), ktrk.q(z)], "yaw_q16": int(round(yaw * 65536)) & 0xFFFF})
    return out


def export(sc: Scene) -> Doc:
    """The document for an extracted scene; raises KitError on a broken convention."""
    verts, faces, edges, groups = _merge(sc)
    b = Builder()
    bid = _faces(sc, b, verts, faces, groups)
    ls, rs = _walk(sc, verts, edges, groups)
    line = [{"l": bid[lv], "r": bid[rv]} for lv, rv in zip(ls, rs, strict=True)]
    meta = sc["scene"]
    doc = b.document(meta["name"], {"kind": "blender", "tool": "ktrk add-on 1"}, line, _checkpoints(ls, groups), _grid(sc, b, line))
    doc["palette"] = {m: list(v["rgb"]) for m, v in sorted(sc["materials"].items()) if m in doc["materials"] or m == meta["far_ground"]}
    doc["mood"] = {"name": meta["mood"], "sun": list(to_engine(meta["sun"]))}
    doc["far_ground"] = meta["far_ground"]
    return doc
