"""Validation of a `.ktrk.json` document (the converter's first stage, M0 subset): returns messages, [] = valid."""

from __future__ import annotations

from racer import ktrk
from racer.ktrk import Doc


def _planarity(p: list[ktrk.Vec]) -> float:
    n = ktrk.normal(p)
    return max(abs(ktrk.dot(n, ktrk.sub(v, p[0]))) for v in p)


def _check_face(doc: Doc, fi: int, face: Doc) -> list[str]:
    ids = face["v"]
    where = f"face {fi}"
    if not 3 <= len(ids) <= 4 or any(not 0 <= i < len(doc["vertices"]) for i in ids):
        return [f"{where}: needs 3-4 valid vertex ids"]
    if face["kind"] not in ktrk.KINDS:
        return [f"{where}: unknown kind {face['kind']!r}"]
    p = ktrk.pts(doc, ids)
    out = []
    if _planarity(p) > ktrk.PLANAR_EPS:
        out.append(f"{where}: not planar within {ktrk.PLANAR_EPS}")
    if face["kind"] in ktrk.GROUND_KINDS:
        out += _check_ground(where, face, p)
    return out


def _check_ground(where: str, face: Doc, p: list[ktrk.Vec]) -> list[str]:
    if ktrk.normal(p)[1] <= 0:
        return [f"{where}: ground normal does not point up"]
    out = []
    if not ktrk.interior(p, ktrk.centroid(p)):
        out.append(f"{where}: wound against the physics' inside test")
    borders = face.get("borders", [])
    if len(borders) > 3:
        out.append(f"{where}: more than 3 borders")
    n = ktrk.normal(p)
    for e in borders:
        d = ktrk.sub(p[(e + 1) % len(p)], p[e])
        wall = (-d[2], 0.0, d[0])
        if ktrk.dot(wall, ktrk.sub(ktrk.centroid(p), p[e])) <= 0 or n[1] <= 0:
            out.append(f"{where}: border {e} faces outward")
    return out


def _check_inner(doc: Doc, fi: int, face: Doc) -> list[str]:
    p = ktrk.pts(doc, face["v"])
    out = []
    for k, inner in enumerate(face.get("inner", [])):
        ip = ktrk.pts(doc, inner["v"])
        if any(abs(v[1] - ktrk.plane_y(p, v[0], v[2])) > ktrk.PLANAR_EPS for v in ip):
            out.append(f"face {fi} inner {k}: not coplanar with its parent")
        if not all(ktrk.interior(p, v, 0.05) for v in ip):
            out.append(f"face {fi} inner {k}: outside its parent's edges")
    return out


def _check_line(doc: Doc) -> list[str]:
    line, nv = doc["racing_line"], len(doc["vertices"])
    if len(line) < 3:
        return ["racing line needs at least 3 segments"]
    if any(not (0 <= s["l"] < nv and 0 <= s["r"] < nv) for s in line):
        return ["racing line: vertex id out of range"]
    bad = [c for c in doc["checkpoints"] if not 0 <= c < len(line)]
    return [f"checkpoint {c} outside the line" for c in bad] + (
        [] if doc["start_grid"] else ["start grid is empty"])


def _check_bounds(doc: Doc) -> list[str]:
    lim = ktrk.GRID // 2 * ktrk.TILE * ktrk.SCALE
    bad = [v for v in doc["vertices"] if abs(v[0]) >= lim or abs(v[2]) >= lim]
    return [f"{len(bad)} vertices outside the {ktrk.GRID}x{ktrk.GRID} tile world"] if bad else []


def validate(doc: Doc) -> list[str]:
    """All problems found in `doc`; an empty list means the converter may go on."""
    out = _check_bounds(doc) + _check_line(doc)
    for fi, face in enumerate(doc["faces"]):
        face_errs = _check_face(doc, fi, face)
        out += face_errs
        if not face_errs:
            out += _check_inner(doc, fi, face)
    return out
