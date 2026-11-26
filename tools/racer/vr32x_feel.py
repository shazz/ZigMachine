"""LOCAL data, committed logic: what the 32X import adds for the ARCADE physics (R82, the "32X feel"; FEEL.md).

- the world scale: the 32X's roads are ~3-3.6 of our units wide where a real one is ROAD_M metres, so a unit is
  ROAD_M / width metres; freds72's speedometer makes his unit FREDS_M metres, so the ground moves FREDS_M / (ROAD_M /
  width) times his at the same km/h. The car scale stays 1: the import's own cars are at their decoded size.
- the AI's speed cues: the 32X's first AI line has a cue per course index (0 = flat out, negative before a corner); ours
  is x/256 of the top: 255 + cue x CUE_GAIN (the 32X's per-group factor is not decoded: the gain is ours), never above our
  geometric bake (cues.py), so a corner the 32X marks 0 inside still gets its radius' limit. Segment j holds course point
  j + 1 (vr32x_course.line).
"""

from __future__ import annotations

import math
import statistics
from typing import Final

from racer import cues, ktrk, mood
from racer.vr32x_tables import Course

ROAD_M: Final = 13.0  # a real two-lane circuit road, metres
FREDS_M: Final = 250 * 3.6 / 108  # freds72's metres a unit: km/h = 900 x units a tick at 30 ticks a second (8.33)
CUE_GAIN: Final = 0.6


def world(doc: ktrk.Doc) -> int:
    """The arcade world scale (Q8) from the road's median width along the racing line."""
    vs = doc["vertices"]
    w = statistics.median(math.dist(vs[s["l"]], vs[s["r"]]) for s in doc["racing_line"]) / ktrk.SCALE
    q = round(256 * FREDS_M * w / ROAD_M)
    return max(mood.SCALE_MIN, min(mood.SCALE_MAX, q))


def ai_cues(doc: ktrk.Doc, course: Course, scale: int) -> list[int]:
    """Per segment: the 32X's cue mapped to ours, capped by our geometric bake."""
    n = len(doc["racing_line"])
    if len(course.lines[0]) < n:
        raise ValueError(f"the AI line has {len(course.lines[0])} points for {n} segments")
    geo = cues.bake(doc, scale)
    sega = [max(1, min(255, round(255 + course.lines[0][(j + 1) % n][2] * CUE_GAIN))) for j in range(n)]
    return [min(a, b) for a, b in zip(geo, sega, strict=True)]


def apply(doc: ktrk.Doc, course: Course | None) -> mood.Mood:
    """The cues into the document's line, and the mood with the scales (the import's ground level 7)."""
    scale = world(doc)
    got = ai_cues(doc, course, scale) if course is not None else cues.bake(doc, scale)
    for s, c in zip(doc["racing_line"], got, strict=True):
        s["cue"] = c
    return mood.Mood(ground_level=7, world=scale)
