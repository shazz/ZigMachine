"""Car Kit export (R82 M5 step 3): a Blender scene's car objects -> the `.kcar.json` document. No `bpy`, so it runs in the gate.

The add-on (tools/racer/blender/car.py) reads the scene into the Track Kit's plain `Scene` dict (`extract`); this turns it into
the document carc.py converts. Conventions:
- one mesh object per PART, named `car_<part>`: wheels, hull, cabin, wing (the near model, drawn in that order, the cabin and
  the wing swapped by where the eye is: carview.zig), shadow (one quad on the ground), lod1 (the far car). Any other `car_*`
  name is refused; objects not named `car_*` are ignored.
- the material name is the car material (carc.MATERIALS: body and stripe take the livery; dark, glass, rim, head, tail, shadow).
- scene custom properties `kcar_name` and `kcar_sun` [x, y, z] (Blender axes): the bake's fixed light, in car space.
Blender is Z-up, the engine y-up: (x, y, z) -> (x, z, y), the Track Kit's reflection. Every face's engine normal is checked
against Blender's, so a face wound inside out is refused. Vertices snap to the 1/128 grid and coincident ones merge.
"""

from __future__ import annotations

import json
from typing import Any

from racer import ktrk
from racer.kit_export import KitError, to_engine
from racer.ktrk import Doc

Scene = dict[str, Any]  # WHY: the add-on's plain JSON-shaped extract (lists and dicts)
PARTS = ("wheels", "hull", "cabin", "wing", "shadow", "lod1")
FORMAT, VERSION = "kcar-json", 1


def area2(p: list[ktrk.Vec]) -> float:
    """|2 x area|^2 of a polygon (0 for a degenerate one: it has no normal)."""
    c = (0.0, 0.0, 0.0)
    for i in range(1, len(p) - 1):
        x = ktrk.cross(ktrk.sub(p[i], p[0]), ktrk.sub(p[i + 1], p[0]))
        c = (c[0] + x[0], c[1] + x[1], c[2] + x[2])
    return ktrk.dot(c, c)


def _part(name: str) -> str:
    part = name[len("car_"):]
    if part not in PARTS:
        raise KitError(f"object {name!r}: no car part {part!r} (one of {', '.join(PARTS)})")
    return part


def _check_winding(name: str, fi: int, pts: list[ktrk.Vec], bnormal: list[float]) -> None:
    if area2(pts) > 1e-12 and ktrk.dot(ktrk.normal(pts), ktrk.unit(to_engine(bnormal))) < 0.5:
        raise KitError(f"{name} face {fi}: the engine's normal disagrees with Blender's (winding)")


def export(sc: Scene) -> Doc:
    """The document for an extracted scene; raises KitError on a broken convention."""
    at: dict[tuple[int, ...], int] = {}
    parts: dict[str, list[Doc]] = {p: [] for p in PARTS}
    for ob in sorted((o for o in sc["objects"] if o["name"].startswith("car_")), key=lambda o: o["name"]):
        part = _part(ob["name"])
        for fi, f in enumerate(ob["faces"]):
            qs = [tuple(ktrk.q(c) for c in to_engine(ob["verts"][i])) for i in f["v"]]
            ids = [at.setdefault(q, len(at)) for q in qs]
            _check_winding(ob["name"], fi, [(q[0] / 128, q[1] / 128, q[2] / 128) for q in qs], f["normal"])
            parts[part].append({"v": ids, "mat": f["mat"]})
    meta = sc["scene"]
    return {"format": FORMAT, "version": VERSION, "name": meta["name"], "sun": list(to_engine(meta["sun"])),
            "vertices": [list(k) for k in sorted(at, key=at.__getitem__)], "parts": parts}


def loads(text: str) -> Doc:
    doc = json.loads(text)
    if doc.get("format") != FORMAT or doc.get("version") != VERSION:
        raise ValueError(f"not a {FORMAT} v{VERSION} document")
    return doc
