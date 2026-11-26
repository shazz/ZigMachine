"""LOCAL ONLY: the decoded-mode steps of vr32x_import.py (the 32X's own course tables instead of the synthesis).

`apply` re-kinds the ground from the surface map, marks the walls, and returns the decoded racing line, checkpoints and
grid; `check` fails loud when the decode and our mesh disagree (a path point or a grid car off our asphalt), which is
also the registration check of the two coordinate systems (the 68000's world and the tile models').
"""

from __future__ import annotations

from racer import ktrk, vr32x_course, vr32x_geom, vr32x_kinds
from racer import vr32x_surface as surf
from racer.vr32x_tables import Course

Decoded = tuple[Course, surf.Layered, list[tuple[int, int, int, int]]]
W = surf.WORLD_PER_UNIT
MAX_OFF = 0.02  # share of the path's points allowed off our asphalt (a kerb sliver the tile models round off)


class DecodeError(ValueError):
    pass


def apply(m: vr32x_geom.Mesh, bins: vr32x_geom.Bins, info: dict[str, object],
          dec: Decoded) -> tuple[list[dict[str, int]], list[int], list[ktrk.Doc]]:
    c, lay, poses = dec
    info["kinds"] = vr32x_kinds.classify(m, lay)
    info["borders"] = vr32x_geom.borders(m, bins)
    seg = vr32x_course.line(m, bins, c, lay)
    info["lap"] = vr32x_course.lap(c)
    info["clockwise"] = vr32x_course.clockwise(c)
    info["pit"] = len(c.pit)
    return seg, vr32x_course.gates(c, lay), vr32x_course.grid(bins, c, lay, poses)


def check(bins: vr32x_geom.Bins, dec: Decoded, grid: list[ktrk.Doc]) -> dict[str, int]:
    c = dec[0]
    off = [i for i, (x, z) in enumerate(c.path) if not bins.under(x / W, z / W, ("track",))]
    cars = [k for k, g in enumerate(grid) if not bins.under(g["pos"][0] / ktrk.SCALE, g["pos"][2] / ktrk.SCALE, ("track",))]
    if len(off) > MAX_OFF * len(c.path) or cars:
        raise DecodeError(f"off our asphalt: path points {off[:12]} ({len(off)} of {len(c.path)}), grid cars {cars}")
    return {"path_off_asphalt": len(off)}
