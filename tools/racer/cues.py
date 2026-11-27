"""The AI's speed cues (R82, the "32X feel"): per racing-line segment, the speed the ARCADE AI holds there.

Like the 32X's own AI lines (a speed cue a point, lower before the corners), but ours, baked by the Track Kit from the
line's geometry: each segment's corner speed from the turn's radius (a circle through the neighbouring centres) under a
lateral-grip limit, then every segment lowered so the car can brake from it to any slower one ahead. The car's velocity is
in freds72's units (km/h = 900 x units a tick) while the ground moves `world` times faster (trk.Scale), so a corner of R
world units is R / world in the physics' units. A cue is x/256 of the FORMULA class's top (feel.py), 1..255; 255 = flat out.
The cart reads it in npc.arcadePedals; CLASSIC never does.
"""

from __future__ import annotations

import math
from typing import Final

from racer import feel, ktrk

A_LAT: Final = 0.008  # the AI's lateral limit, freds72's units a tick squared (fitted on the pilot: FEEL.md)
BRAKE: Final = 0.0035  # the AI's braking, units a tick squared (under our brake pedal's 120 km/h/s = 0.0044)
SPAN: Final = 2  # the circle through centres i - SPAN, i, i + SPAN (the line is resampled every ~3.5 units)


def _centres(doc: ktrk.Doc) -> list[tuple[float, float]]:
    vs = doc["vertices"]
    return [((vs[s["l"]][0] + vs[s["r"]][0]) / 256, (vs[s["l"]][2] + vs[s["r"]][2]) / 256) for s in doc["racing_line"]]


def _radius(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    """The radius of the circle through three points (inf on a straight)."""
    ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
    cross = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    return math.inf if cross < 1e-9 else ab * bc * ca / (2 * cross)


def bake(doc: ktrk.Doc, world: int) -> list[int]:
    """The cue of every segment for a track whose arcade world scale is `world` (Q8)."""
    w = world / 256
    cs = _centres(doc)
    n = len(cs)
    top = feel.CLASSES[0].top / feel.KMH
    v = [min(top, math.sqrt(A_LAT * _radius(cs[i - SPAN], cs[i], cs[(i + SPAN) % n]) / w)) for i in range(n)]
    for _ in range(2):  # backwards twice round the ring: braking zones that wrap past the line
        for i in range(n - 1, -1, -1):
            d = math.dist(cs[i], cs[(i + 1) % n]) / w
            v[i] = min(v[i], math.sqrt(v[(i + 1) % n] ** 2 + 2 * BRAKE * d))
    return [max(1, min(255, round(256 * s / top))) for s in v]


def apply(doc: ktrk.Doc, world: int) -> None:
    """Write the cues into the document's racing line (trackc writes them into the line's flags)."""
    for s, c in zip(doc["racing_line"], bake(doc, world), strict=True):
        s["cue"] = c
