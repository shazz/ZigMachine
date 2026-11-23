"""The "stress city" for M1's renderer spike: a block of tiles each holding about 100 faces (a worst case for
the per-tile face cap), plus a rectangular ring road to fly a camera along. Boxes, not any game's geometry.

Every full tile: 1 ground quad + 3 decals on it + 16 boxes (4 walls + a roof + a roof decal each) = 100.
Boxes are skipped in the two lattice rows on the road, so a road tile holds about 52.
"""

from __future__ import annotations

from racer import ktrk
from racer.ktrk import Builder, Doc

LATTICE, CELL, BOX = 4, 2.0, 1.2  # 4 x 4 boxes of 1.2 units in 2 unit cells of an 8 unit tile
ROAD_W = 2.0  # half width of the ring road
PER_TILE = 100


def _height(tx: int, tz: int, k: int) -> float:
    """Deterministic box height 1.5..6 (a small integer hash, no random module)."""
    return 1.5 + ((tx * 73856093 ^ tz * 19349663 ^ k * 83492791) % 9) * 0.5


def _box(b: Builder, cx: float, cz: float, h: float) -> None:
    r = BOX / 2
    c = [(cx - r, cz - r), (cx + r, cz - r), (cx + r, cz + r), (cx - r, cz + r)]
    low = [b.vert(x, 0.0, z) for x, z in c]
    high = [b.vert(x, h, z) for x, z in c]
    for k in range(4):
        n = (k + 1) % 4
        b.face([low[k], low[n], high[n], high[k]], "prop", "building")
    roof = b.face(high, "prop", "roof")
    b.decal(roof, high, (0.2, 0.8), (0.2, 0.8), "roof_mark")


def _tile(b: Builder, tx: int, tz: int, on_road: bool) -> None:
    x0, z0 = (tx - ktrk.GRID // 2) * ktrk.TILE, (tz - ktrk.GRID // 2) * ktrk.TILE
    ids = [b.vert(x0, 0.0, z0), b.vert(x0 + 8, 0.0, z0), b.vert(x0 + 8, 0.0, z0 + 8), b.vert(x0, 0.0, z0 + 8)]
    ground = b.face(ids, "track" if on_road else "ground", "asphalt" if on_road else "plaza")
    for k in range(3):
        b.decal(ground, ids, (0.1 + 0.3 * k, 0.3 + 0.3 * k), (0.45, 0.55), "street_mark")
    for j in range(LATTICE):
        if on_road and j in (1, 2):
            continue
        for i in range(LATTICE):
            _box(b, x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL, _height(tx, tz, j * LATTICE + i))


def _ring(lo: int, hi: int) -> list[tuple[int, int]]:
    """Tile coordinates of the ring road, counter-clockwise from the bottom-left corner."""
    return ([(x, lo) for x in range(lo, hi)] + [(hi, z) for z in range(lo, hi)]
            + [(x, hi) for x in range(hi, lo, -1)] + [(lo, z) for z in range(hi, lo, -1)])


def _line(b: Builder, ring: list[tuple[int, int]]) -> list[dict[str, int]]:
    """Left / right road-edge vertices at each ring tile centre (miter at the corners)."""
    out = []
    for k, (tx, tz) in enumerate(ring):
        px, pz = tx - ktrk.GRID // 2 + 0.5, tz - ktrk.GRID // 2 + 0.5
        (ax, az), (cx, cz) = ring[k - 1], ring[(k + 1) % len(ring)]
        dx, dz = (cx - ax) / 2.0, (cz - az) / 2.0  # mean direction: a unit step, or a diagonal at a corner
        m = ROAD_W * (2 if abs(dx) == abs(dz) else 1)  # the miter at a 90 degree corner is twice the offset
        px, pz = px * ktrk.TILE, pz * ktrk.TILE
        out.append({"l": b.vert(px - dz * m, 0.0, pz + dx * m), "r": b.vert(px + dz * m, 0.0, pz - dx * m)})
    return out


def build_city(tiles: int = 12) -> Doc:
    """A tiles x tiles block centred on the world, with a ring road along its outermost tiles."""
    lo = (ktrk.GRID - tiles) // 2
    hi = lo + tiles - 1
    b = Builder()
    ring = _ring(lo, hi)
    road = set(ring)
    for tz in range(lo, hi + 1):
        for tx in range(lo, hi + 1):
            _tile(b, tx, tz, (tx, tz) in road)
    line = _line(b, ring)
    grid = [{"segment": 0, "pos": list(b.vertices[line[0]["l"]]), "yaw_q16": 0}]
    meta = {"kind": "stress_city", "tiles": tiles, "faces_per_full_tile": PER_TILE}
    return b.document("stress_city", meta, line, [len(line) // 2, len(line) - 1], grid)
