"""The baked potentially-visible set of Kestrel Racing's converter (R82 M1): which tiles a camera in tile T,
looking along yaw bucket B, can see within R tiles, far to near.

The DEFINITION (the Zig cart's `pvs.zig` runs the same integers; a native test compares them on every tile
and bucket): 33 rays leave the tile centre. Ray j of bucket b points `(j - 16) * RAY_STEP` turns off the
bucket's centre angle (b / 16 turns, 0 = +z, growing toward +x); its direction is the integer pair
`round(4096 * (sin, cos))` stored in the track file, so no trig sits in the comparison. Each ray walks a
grid DDA, one tile a step, up to R steps; a tile's distance is the fewest steps any ray needs. The camera
tile is distance 0 and its 8 neighbours are distance 1 (the camera is not at the tile centre).
"""

from __future__ import annotations

import math

GRID = 32
BUCKETS = 16
RAYS = 33
RAY_STEP = 0.0106  # turns: 33 rays span +-61 degrees, a bucket's half (11) + the half FOV (45) + a margin
R_BAKE = 8
NOT_BAKED = 0xFFFFFFFF

Dirs = list[list[tuple[int, int]]]


def ray_dirs() -> Dirs:
    """[bucket][ray] -> (dx, dz) Q12, the table the track file carries."""
    out = []
    for b in range(BUCKETS):
        row = []
        for j in range(RAYS):
            a = 2 * math.pi * (b / BUCKETS + (j - RAYS // 2) * RAY_STEP)
            row.append((int(math.floor(math.sin(a) * 4096 + 0.5)), int(math.floor(math.cos(a) * 4096 + 0.5))))
        out.append(row)
    return out


def _walk(ox: int, oz: int, dx: int, dz: int, r: int, dist: dict[int, int]) -> None:
    sx, sz, adx, adz = (1 if dx > 0 else -1), (1 if dz > 0 else -1), abs(dx), abs(dz)
    x, z, ix, iz = ox, oz, 0, 0
    for step in range(1, r + 1):
        if adx == 0 and adz == 0:
            return
        lhs, rhs = (32768 + 65536 * ix) * adz, (32768 + 65536 * iz) * adx
        if adz == 0 or (adx != 0 and lhs < rhs):
            x, ix = x + sx, ix + 1
        elif adx == 0 or lhs > rhs:
            z, iz = z + sz, iz + 1
        else:
            x, z, ix, iz = x + sx, z + sz, ix + 1, iz + 1
        if not (0 <= x < GRID and 0 <= z < GRID):
            return
        t = z * GRID + x
        dist[t] = min(dist.get(t, step), step)


def visible(tile: int, bucket: int, r: int, dirs: Dirs) -> list[tuple[int, int]]:
    """[(tile, distance)] far to near (ties by tile id), including the camera tile and its neighbours."""
    ox, oz = tile % GRID, tile // GRID
    dist = {tile: 0}
    for nz in (-1, 0, 1):
        for nx in (-1, 0, 1):
            if (nx or nz) and 0 <= ox + nx < GRID and 0 <= oz + nz < GRID and r >= 1:
                dist[(oz + nz) * GRID + ox + nx] = 1
    for dx, dz in dirs[bucket]:
        _walk(ox, oz, dx, dz, r, dist)
    return sorted(dist.items(), key=lambda e: (-e[1], e[0]))


def bake(tiles: list[int], nonempty: set[int], dirs: Dirs) -> tuple[list[int], list[int]]:
    """(index, lists): index[tile * 16 + bucket] = offset (u16 units) into `lists`, NOT_BAKED if the tile is
    not a camera tile. A list is `[count, e0, e1, ...]`, entry = tile | distance << 10, empty tiles dropped."""
    index = [NOT_BAKED] * (GRID * GRID * BUCKETS)
    lists: list[int] = []
    for t in tiles:
        for b in range(BUCKETS):
            ents = [tl | d << 10 for tl, d in visible(t, b, R_BAKE, dirs) if tl in nonempty]
            index[t * BUCKETS + b] = len(lists)
            lists += [len(ents)] + ents
    return index, lists
