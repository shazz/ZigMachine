"""LOCAL ONLY: the three car classes of a Virtua Racing Deluxe (32X) cartridge dump the user owns, as car files for the cart.

    python3 -I tools/racer/vr32x_car.py [--rom <dump>] [--out <dir>]

Writes, per class, `vr32x_car_<class>.kcr` (a carc.py SET: the player's car and the four AI liveries, each its own model in
the class's own colours, the car ramps recoloured) plus its documents and a report, into the git-ignored directory beside the
dump. Never commit or share what it writes: it is Sega's. This file holds no data (vr32x_carrom.py finds the tables by shape).

Per class: the player's car is the near model with its two axles at the wheels and the class's shadow, its far model the same
body (it is never far from its own camera); each AI livery is its near model with the axles, its far model the livery's own.
Every model goes through carcheck.py (HARD always; SOFT taken: the 32X's near cars are over our 64-face budget) and carc.py.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import carc, kcar_export, vr32x_cargeom, vr_colours
from racer import vr32x_carrom as cr
from racer import vr32x_rom as rom32
from racer.ktrk import Doc

HERE = Path(__file__).resolve().parents[2] / "prototypes/racer_re/vr_local/32x"
DARK = 13  # the skidmarks' ramp (carmodel.SKID_COLOUR): the darkest colour owns it
RAMPS = (12, 14, 15, 16, 17, 18)
PLAYER = 4  # the player's colours' weight in the ramp choice against one AI livery's
RGB = tuple[int, int, int]


class Pieces:
    """A class block's models by their place (vr32x_carrom's layout): near, shadow, axles, the liveries' (near, far)."""

    def __init__(self, ms: list[cr.Model]) -> None:
        self.near = ms[0]
        self.shadow = next(m for m in ms if all(v[1] == 0 for v in m.verts))
        cards = [i for i, m in enumerate(ms) if len(m.polys) <= 2]
        if len(cards) < cr.LIVERIES:
            raise rom32.RomError(f"car block: {len(cards)} sprite cards, want {cr.LIVERIES} (one a livery)")
        self.liveries = [(ms[c - 2], ms[c - 1]) for c in cards[-cr.LIVERIES:]]
        first = cards[-cr.LIVERIES] - 2
        self.axles = (ms[first - 2], ms[first - 1])
        for a in self.axles:
            ys, zs = [v[1] for v in a.verts], [v[2] for v in a.verts]
            if abs(min(ys) + max(ys)) > 16 or abs(min(zs) + max(zs)) > 16:
                raise rom32.RomError("car block: the two models before the liveries are not axles around the origin")
        self.wheels = vr32x_cargeom.wheels(self.liveries[0][1])


def _shades(base: RGB) -> list[RGB]:
    return [tuple(vr_colours.lit(x, lv) for x in base) for lv in range(8)]  # type: ignore[misc]  # [misc] 3 channels


def _cost(cs: dict[int, float], rgb: dict[int, RGB], bases: list[RGB]) -> float:
    return sum(w * min(math.dist(rgb[c], s) for b in bases for s in _shades(b)) for c, w in cs.items())


def palette_for(used: dict[int, float], rgb: dict[int, RGB]) -> tuple[dict[int, tuple[int, int]], dict[int, RGB]]:
    """32X colour -> (ramp, level) and ramp -> RGB. A ramp is one colour at 8 lights (36..99 %), so a base can be any used
    colour or that colour brightened to full (its hue's whole ramp). Ramp 13 (the skidmarks') takes the darkest colour as
    its level 0; then each next ramp takes the base that cuts the area-weighted colour error most."""
    dark = rgb[min(used, key=lambda c: (max(rgb[c]), vr_colours.luma(rgb[c])))]  # the darkest by its brightest channel
    ramps = {DARK: tuple(min(255, round(x * 256 / 92)) for x in dark)}
    full = [tuple(round(x * 255 / max(rgb[c])) for x in rgb[c]) for c in used if max(rgb[c]) > 0]
    cands = list({*(rgb[c] for c in used), *full})
    for r in RAMPS:
        have = list(ramps.values())
        ramps[r] = min(cands, key=lambda b: _cost(used, rgb, [*have, b]))
    at = {c: min(((r, lv) for r in ramps for lv in range(8)), key=lambda p: math.dist(rgb[c], _shades(ramps[p[0]])[p[1]]))
          for c in used}
    return at, ramps  # type: ignore[return-value]  # [return-value] 3-tuples


class Builder:
    """One car document: vertices welded at Q7, faces with their 32X colour until the palette is known."""

    def __init__(self, flip: bool) -> None:
        self.vs: list[tuple[int, int, int]] = []
        self.at: dict[tuple[int, int, int], int] = {}
        self.flip = flip
        self.dropped = 0

    def vid(self, q: tuple[int, int, int]) -> int:
        if q not in self.at:
            self.at[q] = len(self.vs)
            self.vs.append(q)
        return self.at[q]

    def faces(self, m: cr.Model, off: tuple[int, int, int] = (0, 0, 0)) -> list[vr32x_cargeom.Face]:
        out = []
        for p in m.polys:
            ids = [self.vid(vr32x_cargeom.q7(m.verts[i], off)) for i in p.ids]
            ids = ids[::-1] if self.flip else ids
            got = vr32x_cargeom.drawable(self.vs, ids)
            self.dropped += not got
            out += [(f, p.colour) for f in got]
        return out


def model_doc(name: str, body: cr.Model, far: cr.Model | None, pc: Pieces, flip: bool) -> tuple[Doc, Builder]:
    b = Builder(flip)
    wheels = [f for a, c in zip(pc.axles, pc.wheels, strict=True) for f in b.faces(a, c)]
    hull = vr32x_cargeom.order(b.vs, b.faces(body))
    lod1 = vr32x_cargeom.order(b.vs, b.faces(far)) if far else vr32x_cargeom.box(b.vs, hull, b.vid)
    shadow = [{"v": [b.vid(q) for q in vr32x_cargeom.shadow(pc.shadow)], "mat": "shadow"}]
    raw = {"wheels": vr32x_cargeom.order(b.vs, wheels), "hull": hull, "cabin": [], "wing": [], "lod1": lod1}
    parts: dict[str, list[Doc]] = {p: [{"v": f, "colour": c} for f, c in fs] for p, fs in raw.items()}
    parts["shadow"] = shadow
    return {"format": kcar_export.FORMAT, "version": kcar_export.VERSION, "name": name, "sun": [0.0, 1.0, 0.0],
            "vertices": [list(v) for v in b.vs], "parts": parts}, b


def area(doc: Doc, f: Doc) -> float:
    return vr32x_cargeom._area2(vr32x_cargeom._pts([tuple(v) for v in doc["vertices"]], f["v"]))  # [private]


def _weights(docs: list[tuple[Doc, Builder]]) -> tuple[dict[int, float], set[int]]:
    """Each 32X colour's drawn area (the player's PLAYER times), and the player's own colours."""
    used: dict[int, float] = {}
    for k, (d, _) in enumerate(docs):
        for p in ("wheels", "hull", "lod1"):
            for f in d["parts"][p]:
                used[f["colour"]] = used.get(f["colour"], 0.0) + area(d, f) * (PLAYER if k == 0 else 1)
    return used, {f["colour"] for p in ("wheels", "hull") for f in docs[0][0]["parts"][p]}


def _fix(docs: list[tuple[Doc, Builder]], at: dict[int, tuple[int, int]]) -> None:
    for d, _ in docs:
        for p in ("wheels", "hull", "lod1"):
            d["parts"][p] = [{"v": f["v"], "mat": "fixed", "ramp": at[f["colour"]][0], "level": at[f["colour"]][1]}
                             for f in d["parts"][p]]


def car_class(rom: bytes, cls: int, course: list[RGB], allow_soft: bool) -> tuple[bytes, list[str]]:
    """Class `cls` as a set (the player's car, then the AI liveries) and its report lines."""
    pc = Pieces(cr.walk(rom, *cr.blocks(rom)[cls]))
    flip = not vr32x_cargeom.outward([vr32x_cargeom.q7(v) for v in pc.near.verts],
                                     [p.ids for p in pc.near.polys if len(set(p.ids)) >= 3])
    docs = [model_doc(f"{cr.NAMES[cls]}_player", pc.near, None, pc, flip)]
    docs += [model_doc(f"{cr.NAMES[cls]}_{k}", near, far, pc, flip) for k, (near, far) in enumerate(pc.liveries)]
    used, mine = _weights(docs)
    rgb = cr.colours(rom, cls, course)
    at, ramps = palette_for(used, rgb)
    _fix(docs, at)
    blobs = [carc.convert(d, allow_soft) for d, _ in docs]
    err = {c: math.dist(rgb[c], tuple(vr_colours.lit(x, at[c][1]) for x in ramps[at[c][0]])) for c in used}
    lines = [(f"{cr.NAMES[cls]}: {len(docs)} models, flip {flip}, wheels {pc.wheels}, {len(used)} colours on 7 ramps "
             f"{[ramps[r] for r in sorted(ramps)]}, colour error worst {max(err.values()):.0f} mean "
             f"{sum(err.values()) / len(err):.1f}, the player's mean {sum(err[c] for c in mine) / len(mine):.1f}")]
    lines += [f"  {d['name']}: near {len(d['parts']['wheels']) + len(d['parts']['hull'])} faces, far {len(d['parts']['lod1'])}, "
              f"{len(d['vertices'])} vertices, {b.dropped} faces without area dropped" for d, b in docs]
    return carc.pack_set(blobs, [ramps[r] for r in range(12, 19)]), lines


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rom", default=str(HERE / "VirtuaRacingDX.32x"))
    ap.add_argument("--out", default=str(HERE))
    a = ap.parse_args(argv)
    rom = rom32.load(Path(a.rom))
    course = rom32.palette(rom, 0)  # entries 1..31: the grey ramp every course shares
    report = []
    for cls in range(cr.CLASSES):
        blob, lines = car_class(rom, cls, course, allow_soft=True)
        (Path(a.out) / f"vr32x_car_{cr.NAMES[cls]}.kcr").write_bytes(blob)
        report += lines
    (Path(a.out) / "vr32x_car_report.txt").write_text("\n".join(report) + "\n")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
