"""The `.ktrk.json` intermediate of Kestrel Racing's Track Kit (docs/ports/kestrel_racing, R82, M0).

A neutral description of a track: vertices on a 1/128 unit grid (ints), faces (up to 4 vertices, with a
material, a kind and decals as `inner` faces), the racing line, checkpoints and a start grid. Everything
after the Blender add-on (the converter, the Lua reference harness, the Zig cart) reads this and nothing
else. Face flags use the layout of the PORT_PLAN §3.1 (bit 0 dual-sided, 1 quad, 2 asphalt, 3 has inner
faces, 4 ground, 5-7 border count), a layout chosen for the port, not copied data.

World: 32 x 32 tiles of 8 units, centred on the origin (x, z in -128..128); y is up. A ground face is
wound so that its normal points up and the point-in-polygon test of the physics (all edge normals
`(-dz, dx)` positive) holds; a border edge `i` runs from vertex i to i+1 and its wall normal points inside.
"""

from __future__ import annotations

import json
import math
from typing import Any

SCALE = 128
TILE = 8
GRID = 32
FLAG_DUAL, FLAG_QUAD, FLAG_ASPHALT, FLAG_INNER, FLAG_GROUND = 1, 2, 4, 8, 16
GROUND_KINDS = ("track", "ground")
KINDS = GROUND_KINDS + ("wall", "prop")
PLANAR_EPS = 0.12

Vec = tuple[float, float, float]
Doc = dict[str, Any]


def q(x: float) -> int:
    """World units -> the 1/128 grid (round half up, so the result never depends on float noise)."""
    return int(math.floor(x * SCALE + 0.5))


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def unit(a: Vec) -> Vec:
    n = math.sqrt(dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n)


def pts(doc: Doc, ids: list[int]) -> list[Vec]:
    return [tuple(c / SCALE for c in doc["vertices"][i]) for i in ids]  # type: ignore[misc]  # [tuple-size] 3 ints by schema


def normal(p: list[Vec]) -> Vec:
    """Face normal as the engine computes it: (last - first) x (second - first), normalised."""
    return unit(cross(sub(p[-1], p[0]), sub(p[1], p[0])))


def interior(p: list[Vec], at: Vec, slack: float = 0.0) -> bool:
    """Point-in-convex-polygon on the XZ plane, the physics' is_inside rule (an edge test per side)."""
    prev = p[-1]
    for cur in p:
        if (prev[2] - cur[2]) * (at[0] - prev[0]) + (cur[0] - prev[0]) * (at[2] - prev[2]) < -slack:
            return False
        prev = cur
    return True


def plane_y(p: list[Vec], x: float, z: float) -> float:
    n = normal(p)
    return p[0][1] - (n[0] * (x - p[0][0]) + n[2] * (z - p[0][2])) / n[1]


def centroid(p: list[Vec]) -> Vec:
    return (sum(v[0] for v in p) / len(p), sum(v[1] for v in p) / len(p), sum(v[2] for v in p) / len(p))


def face_flags(face: Doc) -> int:
    f = FLAG_DUAL if face.get("dual") else 0
    f |= FLAG_QUAD if len(face["v"]) == 4 else 0
    f |= FLAG_ASPHALT if face["kind"] == "track" else 0
    f |= FLAG_INNER if face.get("inner") else 0
    f |= FLAG_GROUND if face["kind"] in GROUND_KINDS else 0
    return f | (len(face.get("borders", [])) << 5)


def dumps(doc: Doc) -> str:
    """Deterministic text: sorted keys, fixed separators, ints only, one trailing newline."""
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def loads(text: str) -> Doc:
    doc = json.loads(text)
    if doc.get("format") != "ktrk-json" or doc.get("version") != 1:
        raise ValueError("not a ktrk-json v1 document")
    return doc


def tile_faces(doc: Doc, ground_only: bool = False) -> dict[tuple[int, int], list[int]]:
    """Face indices per tile by 2D bounding box (the engine's voxel binning), tile (0,0) at world -128."""
    out: dict[tuple[int, int], list[int]] = {}
    half = GRID // 2
    for fi, face in enumerate(doc["faces"]):
        if ground_only and face["kind"] not in GROUND_KINDS:
            continue
        p = pts(doc, face["v"])
        x0, x1 = (math.floor(min(v[0] for v in p) / TILE) + half, math.ceil(max(v[0] for v in p) / TILE) - 1 + half)
        z0, z1 = (math.floor(min(v[2] for v in p) / TILE) + half, math.ceil(max(v[2] for v in p) / TILE) - 1 + half)
        for tz in range(z0, z1 + 1):
            for tx in range(x0, x1 + 1):
                out.setdefault((tx, tz), []).append(fi)
    return out


class Builder:
    """Collects vertices (deduplicated on the grid) and faces for one track."""

    def __init__(self) -> None:
        self.vertices: list[list[int]] = []
        self._index: dict[tuple[int, int, int], int] = {}
        self.faces: list[Doc] = []

    def vert(self, x: float, y: float, z: float) -> int:
        key = (q(x), q(y), q(z))
        if key not in self._index:
            self._index[key] = len(self.vertices)
            self.vertices.append(list(key))
        return self._index[key]

    def face(self, ids: list[int], kind: str, mat: str, borders: list[tuple[int, int]] | None = None,
             dual: bool = False) -> Doc:
        """Add a face; a ground face is re-wound so its normal points up. `borders` are vertex-id pairs."""
        doc = {"vertices": self.vertices}
        if kind in GROUND_KINDS and normal(pts(doc, ids))[1] < 0:
            ids = ids[::-1]
        f: Doc = {"v": ids, "kind": kind, "mat": mat}
        if dual:
            f["dual"] = True
        edges = [k for k in range(len(ids)) for a, b in (borders or []) if {ids[k], ids[(k + 1) % len(ids)]} == {a, b}]
        if edges:
            f["borders"] = edges
        self.faces.append(f)
        return f

    def decal(self, parent: Doc, corners: list[int], u: tuple[float, float], t: tuple[float, float],
              mat: str) -> None:
        """An inner face on a road quad given as corners (left0, right0, right1, left1): u runs along
        (corner 0 -> 3), t across (0 -> 1); the points are projected on the parent's plane."""
        doc = {"vertices": self.vertices}
        p = pts(doc, corners)
        out = []
        for uu, tt in ((u[0], t[0]), (u[0], t[1]), (u[1], t[1]), (u[1], t[0])):
            a = tuple(p[0][c] + (p[1][c] - p[0][c]) * tt for c in range(3))
            b = tuple(p[3][c] + (p[2][c] - p[3][c]) * tt for c in range(3))
            x, z = a[0] + (b[0] - a[0]) * uu, a[2] + (b[2] - a[2]) * uu
            out.append(self.vert(x, plane_y(p, x, z), z))
        parent.setdefault("inner", []).append({"v": out, "mat": mat})

    def document(self, name: str, meta: Doc, line: list[dict[str, int]], checkpoints: list[int],
                 start_grid: list[Doc]) -> Doc:
        mats = sorted({f["mat"] for f in self.faces} | {i["mat"] for f in self.faces for i in f.get("inner", [])})
        return {"format": "ktrk-json", "version": 1, "name": name, "tile_size": TILE, "grid": [GRID, GRID],
                "vertex_scale": SCALE, "vertices": self.vertices, "materials": mats, "faces": self.faces,
                "racing_line": line, "checkpoints": checkpoints, "start_grid": start_grid, "generator": meta}
