"""Track Kit conversion (R82 M5): an AUTHORED `.ktrk.json` (the Blender add-on's export) -> the cart's binary track.

An authored document carries what the generated test tracks get from trackc's fixed tables:
    "palette":    {material: [r, g, b]}   the track's own ramps (ints 0..255: the colour of a face square to the sun)
    "mood":       {"name": str, "sun": [x, y, z]}   the fixed sun the face colours are baked against (bake.py); optional
                  "sky": [r,g,b, r,g,b] (top, horizon), "hills": 3 x [r,g,b] flat (the backdrop), "backdrop": "hills" | "docks" | "peaks"
    "far_ground": material                the colour of the ground beyond the draw distance (it goes on ramp 1)
The far ground's level is the bake of a face square to the up axis (no seam at the draw distance); it and the look go into
the file's mood block (mood.py). The budget check (budget.py) runs first and refuses the track over a limit; then trackc's validation and conversion run
with the track's palette and the baked shading. The test oval and the stress city do not come through here (their bytes
are pinned as trackc writes them).
"""

from __future__ import annotations

from typing import Final

from racer import bake, budget, cues, ktrk, limits, mood, trackc
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


def _rgbs(doc: Doc, key: str, n: int) -> list[tuple[int, int, int]] | None:
    v = doc["mood"].get(key)
    if v is None:
        return None
    if not (isinstance(v, list) and len(v) == 3 * n):
        raise trackc.ConvertError(f"mood {key} {v!r}: want {n} x [r, g, b] flattened ({3 * n} ints)")
    return [_rgb(key, v[3 * k:3 * k + 3]) for k in range(n)]


def look(doc: Doc) -> mood.Mood:
    """The mood block: the far ground on ramp 1 at the baked flat level, the sky, the backdrop (the oval's where unset)."""
    base = mood.Mood()
    shape = doc["mood"].get("backdrop", mood.BACKDROPS[0])
    if shape not in mood.BACKDROPS:
        raise trackc.ConvertError(f"mood backdrop {shape!r}: one of {', '.join(mood.BACKDROPS)}")
    sky, hills = _rgbs(doc, "sky", 2), _rgbs(doc, "hills", 3)
    clock = doc["mood"].get("clock", [0, 0])
    if not (isinstance(clock, list) and len(clock) == 2 and all(isinstance(c, int) for c in clock)):
        raise trackc.ConvertError(f"mood clock {clock!r}: want [start, extension] in seconds (0 = computed)")
    draw_r = doc["mood"].get("draw_r", 0)
    if not isinstance(draw_r, int):
        raise trackc.ConvertError(f"mood draw_r {draw_r!r}: the draw distance cap in tiles (0 = none)")
    haze = _haze(doc)
    m = mood.Mood(GROUND_RAMP, bake.level((0.0, 1.0, 0.0), sun(doc)), 0, mood.BACKDROPS.index(shape),
                  (sky[0], sky[1]) if sky else base.sky, (hills[0], hills[1], hills[2]) if hills else base.hills,
                  (clock[0], clock[1]), draw_r, *haze, *_scale(doc))
    try:
        m.pack()  # its range checks (a clock over mood.MAX_CLOCK)
    except ValueError as e:
        raise trackc.ConvertError(str(e)) from e
    return m


# R82 32X feel (FEEL.md): a Track Kit track is authored at about a metre a unit (its roads 10-12 units), far smaller than
# freds72's world (his speedometer makes a unit ~8.3 m). Its ARCADE scales: the ground moves KIT_WORLD x freds72's at the
# same km/h (2 m a unit: roads 20-24 m, laps 1.3-2 km) and the car is drawn KIT_CAR x the GT (4.5 m long at 2 m a unit).
KIT_WORLD: Final = 1067  # Q8: 8.33 / 2
KIT_CAR: Final = 640  # Q8: 2.25 units / the GT's 0.9


def _scale(doc: Doc) -> tuple[int, int]:
    """The arcade world and car scales (mood `world`, `car`, Q8), the Kit's by default."""
    w, c = doc["mood"].get("world", KIT_WORLD), doc["mood"].get("car", KIT_CAR)
    if not all(isinstance(x, int) and mood.SCALE_MIN <= x <= mood.SCALE_MAX for x in (w, c)):
        raise trackc.ConvertError(f"mood world {w!r} / car {c!r}: Q8 ints {mood.SCALE_MIN}..{mood.SCALE_MAX}")
    return w, c


def _haze(doc: Doc) -> tuple[tuple[int, int, int], int, int]:
    """M6: the horizon haze (mood `haze` [r, g, b], `haze_start` x/256 of R, `haze_strength` x/255); none where unset."""
    strength = doc["mood"].get("haze_strength", 0)
    if strength == 0:
        return (0, 0, 0), 0, 0  # the panel's default: no haze
    rgb, start = _rgb("haze", doc["mood"].get("haze")), doc["mood"].get("haze_start", 0)
    if not (isinstance(start, int) and isinstance(strength, int) and 0 <= start <= 255 and 1 <= strength <= 255):
        raise trackc.ConvertError(f"mood haze start {start!r} / strength {strength!r}: ints 0..255 / 1..255")
    return rgb, start, strength


def convert(doc: Doc) -> bytes:
    errs = budget.problems(doc)
    if errs:
        raise trackc.ConvertError("; ".join(errs[:5]))
    at, mats = ramps(doc)
    m = look(doc)
    doc = {**doc, "racing_line": [dict(s) for s in doc["racing_line"]]}  # the cues go on a copy
    cues.apply(doc, m.world)
    blob = trackc.convert(doc, mats, shade=bake.shader(at, sun(doc)), look=m)
    n, room = mood.haze_room(blob)
    if m.haze_strength and n > room:
        raise trackc.ConvertError(f"mood haze: {n} face colours, the palette has {room} spare entries (the cart's haze pool)")
    return blob
