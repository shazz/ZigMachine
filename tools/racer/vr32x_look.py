"""LOCAL ONLY importer options (R82 32X look, docs/ports/kestrel_racing/LOOK.md): what vr32x_import.py adds to a 32X course
beyond its tiles: the panorama file (vr32x_pan.py -> panc.py), the water's tones (vr32x_water.py), the placed objects
(vr32x_objects.py). Holds no data.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass

from racer import panc, vr32x_colours, vr32x_pan
from racer.vr32x_rom import RGB

PAN_U0 = 160  # the 32X shows strip column x - heading / 64 at screen column x: the column ahead is 160 + our yaw / 64


@dataclass(frozen=True)
class LookOpts:
    """R82 32X look (docs/ports/kestrel_racing/LOOK.md): the importer's look options."""
    water: bool = False  # item 3 (vr32x_water.py): the level water faces alternate two tones
    pano: bool = False  # item 1 (vr32x_pan.py, panc.py): the course's panorama as vr32x_<n>.pan, on PAN_RAMPS ramps
    pan_u0: int = PAN_U0  # the panorama's texel straight ahead at yaw 0
    pan_flip: bool = False  # the strip mirrored (the 32X's scroll runs the other way round from our yaw)
    objects: bool = False  # item 2 (vr32x_objects.py): the gantries and landmarks placed outside the tile maps


NONE = LookOpts()
PAN_RAMPS = 3  # 24 entries: the 32X's strips have 23-29 colours (the rarest nearest pairs merged)
PAN_UP, PAN_LOW = 80, 72  # rows kept above / from the horizon: the cart's level horizon is row 100 of 12..188, 1.25 px a row


def pano(rom: bytes, k: int, opts: LookOpts) -> tuple[bytes, RGB]:
    """Course k's panorama as the cart's .PAN, on the ramps colours(reserve=PAN_RAMPS) left free, and its top row's
    commonest colour (the mood's sky: what a camera pitched up sees over the strip)."""
    p = vr32x_pan.panoramas(rom)[k]
    px = p.pixels
    if opts.pan_flip:
        px = b"".join(px[r * p.width:(r + 1) * p.width][::-1] for r in range(p.height))
    first = 16 + 8 * vr32x_colours.reserved(PAN_RAMPS)[0]
    rows, px, hz = panc.crop(p.width, p.height, px, p.horizon, PAN_UP, PAN_LOW)
    top = px[:p.width]
    sky = p.palette[max(set(top), key=top.count)]
    return panc.encode(p.width, rows, px, p.palette, hz, first, opts.pan_u0, 8 * PAN_RAMPS), sky


def add_args(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--water", action="store_true", help="the level water faces alternate two tones (vr32x_water.py)")
    ap.add_argument("--pano", action="store_true", help="write the course's panorama (vr32x_<n>.pan; 3 ramps kept for it)")
    ap.add_argument("--pan-u0", type=int, default=PAN_U0, help="the panorama's texel straight ahead at yaw 0")
    ap.add_argument("--pan-flip", action="store_true", help="mirror the panorama strip")
    ap.add_argument("--objects", action="store_true", help="add the START / C.P. gantries and the landmarks")


def of(args: argparse.Namespace) -> LookOpts:
    return LookOpts(args.water, args.pano, args.pan_u0, args.pan_flip, args.objects)
