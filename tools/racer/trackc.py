"""Track converter v0 for Kestrel Racing (R82 M1): `.ktrk.json` -> the cart's binary track (`.ktrk`).

    python3 -I tools/racer/trackc.py in.ktrk.json -o out.ktrk

Little-endian, 4-aligned. A 128-byte header of 32 u32 words, then blocks (offsets in the header):
palette (RGB x ramps), vertices (i16 x3, 1/128 unit), faces + inner faces (32 B records), tile face lists,
ray directions, the baked PVS (pvs_bake.py), the racing line (centre Q16 x3, yaw turns Q16), the start
grid. The CRC-32 covers everything after the header. The cart refuses a bad magic, version or CRC.
Face record: v[4] u16 | flags u8 | nv u8 | colour u8 | inner_n u8 | n[3] i16 (Q14) | pad u16 |
cp i32 (n . v0, Q21) | inner_first u32 | pad u32.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ktrk, ktrk_check, pvs_bake  # noqa: E402
from racer.ktrk import Doc  # noqa: E402

MAGIC, VERSION, HEADER = 0x4B52544B, 1, 128
LIGHT = (0.4, 0.8, 0.45)
MATERIALS = {  # name -> (ramp, full-light RGB): our own palette, 12 of the 30 ramps used so far
    "asphalt": (0, (96, 98, 104)), "grass": (1, (70, 150, 60)), "kerb_a": (2, (220, 40, 40)),
    "kerb_b": (3, (235, 235, 235)), "paint": (4, (240, 240, 230)), "paint_start": (5, (250, 210, 40)),
    "wall": (6, (150, 140, 120)), "building": (7, (150, 120, 100)), "plaza": (8, (130, 130, 120)),
    "roof": (9, (90, 100, 130)), "roof_mark": (10, (230, 180, 60)), "street_mark": (11, (210, 210, 200)),
}
NRAMPS = len(MATERIALS)


class ConvertError(ValueError):
    """The document cannot become a cart track."""


def colour(mat: str, n: ktrk.Vec) -> int:
    """Palette index 16 + ramp * 8 + a light level baked from n . L (0..7)."""
    if mat not in MATERIALS:
        raise ConvertError(f"material {mat!r} has no palette ramp")
    lam = max(0.0, ktrk.dot(n, ktrk.unit(LIGHT)))
    return 16 + MATERIALS[mat][0] * 8 + min(7, int((0.25 + 0.75 * lam) * 8))


def _face(doc: Doc, face: Doc, mat: str, flags: int, inner: tuple[int, int]) -> bytes:
    ids = face["v"]
    p = ktrk.pts(doc, ids)
    n = ktrk.normal(p)
    n14 = [int(round(c * 16384)) for c in n]
    v0 = doc["vertices"][ids[0]]
    cp = sum(n14[i] * v0[i] for i in range(3))
    v = (ids + [ids[-1]] * 4)[:4]
    return struct.pack("<4HBBBB3hHiII", *v, flags, len(ids), colour(mat, n), inner[1], *n14, 0, cp, inner[0], 0)


def _faces(doc: Doc) -> tuple[bytes, bytes]:
    top, inner = [], []
    for f in doc["faces"]:
        sub = f.get("inner", [])
        flags = ktrk.face_flags(f) & 0x1F
        top.append(_face(doc, f, f["mat"], flags, (len(inner), len(sub))))
        for i in sub:
            inner.append(_face(doc, i, i["mat"], flags | 0x20, (0, 0)))
    return b"".join(top), b"".join(inner)


def _tiles(doc: Doc) -> tuple[bytes, bytes, set[int]]:
    per = ktrk.tile_faces(doc)
    first, lists, full = [], [], set()
    for t in range(ktrk.GRID * ktrk.GRID):
        first.append(len(lists))
        ids = per.get((t % ktrk.GRID, t // ktrk.GRID), [])
        lists += ids
        if ids:
            full.add(t)
    first.append(len(lists))
    return struct.pack(f"<{len(first)}I", *first), _pad(struct.pack(f"<{len(lists)}H", *lists)), full


def _pad(b: bytes) -> bytes:
    return b + b"\0" * (-len(b) % 4)


def _line(doc: Doc) -> tuple[bytes, list[tuple[int, int]]]:
    """Per segment the centre (Q16 x3) and the yaw (turns Q16) toward the next centre."""
    vs = doc["vertices"]
    cs = [tuple((vs[s["l"]][k] + vs[s["r"]][k]) * 256 for k in range(3)) for s in doc["racing_line"]]
    out, tiles = b"", []
    for i, c in enumerate(cs):
        nx = cs[(i + 1) % len(cs)]
        yaw = int(round((math.atan2(nx[0] - c[0], nx[2] - c[2]) / (2 * math.pi)) % 1.0 * 65536)) & 0xFFFF
        out += struct.pack("<3iHH", *c, yaw, 0)
        tiles.append((int(c[0] // 65536 // ktrk.TILE) + 16, int(c[2] // 65536 // ktrk.TILE) + 16))
    return out, tiles


def _camera_tiles(line_tiles: list[tuple[int, int]]) -> list[int]:
    """Every tile within one of a racing-line tile: the camera (<= 8 units behind the line) is there."""
    out = set()
    for x, z in line_tiles:
        for dz in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if 0 <= x + dx < ktrk.GRID and 0 <= z + dz < ktrk.GRID:
                    out.add((z + dz) * ktrk.GRID + x + dx)
    return sorted(out)


def convert(doc: Doc) -> bytes:
    errs = ktrk_check.validate(doc)
    if errs:
        raise ConvertError("; ".join(errs[:5]))
    pal = b"".join(bytes(rgb) + b"\0" for _, rgb in sorted(MATERIALS.values()))
    verts = _pad(b"".join(struct.pack("<3h", *v) for v in doc["vertices"]))
    faces, inner = _faces(doc)
    tfirst, tlists, full = _tiles(doc)
    dirs = pvs_bake.ray_dirs()
    rays = struct.pack("<%dh" % (16 * 33 * 2), *[c for row in dirs for d in row for c in d])
    line, line_tiles = _line(doc)
    index, lists = pvs_bake.bake(_camera_tiles(line_tiles), full, dirs)
    grid = b"".join(struct.pack("<3iHH", *(c * 512 for c in g["pos"]), g["yaw_q16"], 0) for g in doc["start_grid"])
    blocks = [pal, verts, faces, inner, tfirst, tlists, rays, struct.pack(f"<{len(index)}I", *index),
              _pad(struct.pack(f"<{len(lists)}H", *lists)), line, grid]
    offs, at = [], HEADER
    for b in blocks:
        offs.append(at)
        at += len(b)
    name = doc["name"].encode()[:24].ljust(24, b"\0")
    words = [MAGIC, VERSION, 0, at, len(doc["vertices"]), len(doc["faces"]), sum(len(f.get("inner", [])) for f in doc["faces"]),
             len(doc["racing_line"]), len(doc["start_grid"]), NRAMPS, pvs_bake.R_BAKE, len(doc["checkpoints"])] + offs
    head = struct.pack(f"<{len(words)}I", *words) + b"\0" * (HEADER - 24 - 4 * len(words)) + name
    body = b"".join(blocks)
    crc = zlib.crc32(body)
    return head[:8] + struct.pack("<I", crc) + head[12:] + body


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args(argv)
    try:
        blob = convert(ktrk.loads(Path(args.src).read_text()))
    except (ConvertError, ValueError) as e:
        print(f"trackc: {e}", file=sys.stderr)
        return 1
    Path(args.out).write_bytes(blob)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
