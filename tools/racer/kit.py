"""Track Kit conversion (R82 M5): an AUTHORED `.ktrk.json` (the Blender add-on's export) -> the cart's binary track.

An authored document carries what the generated test tracks get from trackc's fixed tables:
    "palette":    {material: [r, g, b]}   the track's own ramps (ints 0..255: the colour of a face square to the sun)
    "mood":       {"name": str, "sun": [x, y, z]}   the fixed sun the face colours are baked against (bake.py)
    "far_ground": material                the colour of the ground beyond the draw distance (it goes on ramp 1)
The budget check (budget.py) runs first and refuses the track over a limit; then trackc's validation and conversion run
with the track's palette and the baked shading. The test oval and the stress city do not come through here (their bytes
are pinned as trackc writes them).
"""

from __future__ import annotations

from racer import bake, budget, ktrk, limits, trackc
from racer.ktrk import Doc

GROUND_RAMP = 1  # trackset.zig: the far ground is ramp 1 on every track


def _rgb(name: str, v: object) -> tuple[int, int, int]:
    if not (isinstance(v, list) and len(v) == 3 and all(isinstance(c, int) and 0 <= c <= 255 for c in v)):
        raise trackc.ConvertError(f"palette {name!r}: want [r, g, b] ints 0..255, got {v!r}")
    return (v[0], v[1], v[2])


def ramps(doc: Doc) -> tuple[dict[str, int], dict[str, tuple[int, tuple[int, int, int]]]]:
    """(material -> ramp, trackc's mats table: the track's ramps, the car's, pads for the ramps in between)."""
    for key in ("palette", "mood", "far_ground"):
        if key not in doc:
            raise trackc.ConvertError(f"an authored track needs {key!r} (see tools/racer/kit.py)")
    pal = {name: _rgb(name, v) for name, v in doc["palette"].items()}
    used = {f["mat"] for f in doc["faces"]} | {i["mat"] for f in doc["faces"] for i in f.get("inner", [])}
    missing = sorted(used - set(pal))
    if missing:
        raise trackc.ConvertError(f"materials {missing} have no palette colour")
    far = doc["far_ground"]
    if far not in pal:
        raise trackc.ConvertError(f"far_ground {far!r} is not in the palette")
    rest = sorted(set(pal) - {far})
    free = [r for r in limits.FREE_RAMPS if r != GROUND_RAMP]
    if len(rest) + 1 > len(limits.FREE_RAMPS):
        raise trackc.ConvertError(f"HARD limit: {len(rest) + 1} colour ramps > {len(limits.FREE_RAMPS)}")
    at = {far: GROUND_RAMP, **dict(zip(rest, free, strict=False))}
    mats = {**limits.CAR_RAMPS, **{m: (r, pal[m]) for m, r in at.items()}}
    taken = {r for r, _ in mats.values()}
    for r in range(max(taken)):
        if r not in taken:
            mats[f"pad{r}"] = (r, (128, 128, 128))
    return at, mats


def sun(doc: Doc) -> ktrk.Vec:
    s = doc["mood"].get("sun")
    if not (isinstance(s, list) and len(s) == 3 and s[1] > 0):
        raise trackc.ConvertError(f"mood sun {s!r}: want [x, y, z] with y > 0 (above the horizon)")
    return (float(s[0]), float(s[1]), float(s[2]))


def convert(doc: Doc) -> bytes:
    errs = budget.problems(doc)
    if errs:
        raise trackc.ConvertError("; ".join(errs[:5]))
    at, mats = ramps(doc)
    return trackc.convert(doc, mats, shade=bake.shader(at, sun(doc)))
