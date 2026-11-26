"""Car converter for Kestrel Racing (R82 M5 step 3): `.kcar.json` -> the cart's binary car (`.kcar`).

    python3 -I tools/racer/carc.py tools/racer/cars/gt.kcar.json -o apps/zig/assets/screens/racer/gt.kcar [--allow-soft]

The budget check first (carcheck.py: HARD refusals always, SOFT ones unless --allow-soft), then the baked colours: every
face stores its own palette index, the level baked once from its normal against the car's fixed sun (bake.level: 4..7),
nothing lit at run time, nothing dithered. The car turns and its light turns with it (a flat-shaded car shows that least).
Little-endian, 4-aligned. A 64-byte header of 16 u32 words:
  0 magic 'KCAR' | 1 version | 2 vertices | 3 faces | 4..9 the end face of each part (wheels, hull, cabin, wing, shadow,
  lod1: the parts follow each other in that order) | 10 the wing's front edge (i32, Q7 forward: carview swaps the cabin and
  the wing by the eye's side of it) | 11 CRC-32 of everything after the header | 12..15 zero
then the vertices (i16 x3, Q7, car space: x right, y up, z forward; padded to 4) and the faces as trk.Face's 32-byte records
(trackc's layout). Face flags: 0x40 body, 0x80 stripe (the two livery recolours, carmodel.zig), 0x10 the shadow.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import bake, carcheck, ktrk  # noqa: E402
from racer.kcar_export import PARTS, loads  # noqa: E402
from racer.ktrk import Doc  # noqa: E402

MAGIC, VERSION, HEADER = 0x5241434B, 1, 64
FLAG_SHADOW, FLAG_BODY, FLAG_STRIPE = 0x10, 0x40, 0x80
# material -> (ramp, flags, fixed level or None = baked). Ramps: 12 the player's body (track palette), 13 dark, 14 glass,
# 18 the white livery (the cart's palette). body / stripe are stored on ramp 12 and recoloured by the livery (carmodel.zig).
MATERIALS = {
    "body": (12, FLAG_BODY, None), "stripe": (12, FLAG_STRIPE, None), "dark": (13, 0, None), "glass": (14, 0, None),
    "rim": (18, 0, None), "head": (18, 0, 7), "tail": (12, 0, 7), "shadow": (0, FLAG_SHADOW, 0),
}


class CarError(ValueError):
    """The document cannot become a cart car."""


def _record(doc: Doc, f: Doc, sun: ktrk.Vec) -> bytes:
    ids = f["v"]
    n = ktrk.normal(ktrk.pts(doc, ids))
    n14 = [round(c * 16384) for c in n]
    v0 = doc["vertices"][ids[0]]
    cp = sum(n14[i] * v0[i] for i in range(3))
    ramp, flags, fixed = MATERIALS[f["mat"]]
    colour = 0 if flags == FLAG_SHADOW else 16 + ramp * 8 + (bake.level(n, sun) if fixed is None else fixed)
    v = (ids + [ids[-1]] * 4)[:4]
    return struct.pack("<4HBBBB3hHiII", *v, flags, len(ids), colour, 0, *n14, 0, cp, 0, 0)


def convert(doc: Doc, allow_soft: bool = False) -> bytes:
    bad = [p for p in carcheck.problems(doc) if p.startswith("HARD") or not allow_soft]
    if bad:
        raise CarError("; ".join(bad))
    sun = tuple(doc["sun"])
    faces, ends = b"", []
    for p in PARTS:
        faces += b"".join(_record(doc, f, sun) for f in doc["parts"].get(p, []))  # type: ignore[arg-type]  # [arg-type] 3 floats
        ends.append(len(faces) // 32)
    vs = b"".join(struct.pack("<3h", *v) for v in doc["vertices"])
    vs += b"\0" * (-len(vs) % 4)
    body = vs + faces
    wing = [doc["vertices"][i][2] for f in doc["parts"].get("wing", []) for i in f["v"]]
    head = struct.pack("<4I6IiI4I", MAGIC, VERSION, len(doc["vertices"]), ends[-1], *ends, max(wing, default=-128),
                       zlib.crc32(body), 0, 0, 0, 0)
    return head + body


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--allow-soft", action="store_true", help="take a car over the SOFT budget (never past a HARD limit)")
    a = ap.parse_args(argv)
    try:
        blob = convert(loads(Path(a.src).read_text()), a.allow_soft)
    except (CarError, ValueError) as e:
        print(f"carc: {e}", file=sys.stderr)
        return 1
    Path(a.out).write_bytes(blob)
    return 0


if __name__ == "__main__":
    sys.exit(main())
