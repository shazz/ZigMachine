"""A Tiled JSON map (as written by levels.py export, desktop Tiled or WebTiled) -> a level.

Accepts what the editors legitimately rewrite: properties as a list or the old
{name: value} object, layer data as an array or base64 (zlib / gzip / none),
an embedded or an external tileset (only its firstgid is needed), markers as
rectangles, points or tile objects, with "type" or "class". Anything else
that is not exactly a level raises LevelError naming the map, layer and
position. Nothing is clamped or guessed.
"""
import base64
import gzip
import zlib

from levels_model import (LevelError, Mission, WORLD_LEN, check_briefing, check_field, check_mission,
                          check_world)
from levels_tiled import FIELDS, MARKER_GID, MARKERS, MISSION_LAYER, TILE_H, TILE_W, WORLD_LAYER

FLIP_BITS = 0xF0000000
PROPS = {'record', 'briefing', *FIELDS}


def properties(obj: dict, where: str) -> dict:
    raw = obj.get('properties', [])
    if isinstance(raw, dict):  # Tiled < 1.2: {"name": value} + "propertytypes"
        return dict(raw)
    out = {}
    for p in raw:
        if p['name'] in out:
            raise LevelError(f'{where}: property "{p["name"]}" appears twice')
        out[p['name']] = p.get('value')
    return out


def as_int(value: object, where: str) -> int:
    """An int property as any editor stores it: 5, 5.0 or "5"."""
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str) and value.strip().lstrip('-').isdigit():
        return int(value)
    return check_field(value, -2**31, 2**31, where)


def layer_data(layer: dict, where: str) -> list[int]:
    data = layer.get('data')
    if layer.get('encoding', 'csv') != 'base64':
        return list(data)
    raw = base64.b64decode(data)
    comp = layer.get('compression', '')
    if comp == 'zlib':
        raw = zlib.decompress(raw)
    elif comp == 'gzip':
        raw = gzip.decompress(raw)
    elif comp:
        raise LevelError(f'{where}: layer compression "{comp}" is not supported (use CSV, zlib or gzip)')
    return [int.from_bytes(raw[i:i + 4], 'little') for i in range(0, len(raw), 4)]


def find_layer(doc: dict, name: str, kind: str, where: str) -> dict:
    found = [lay for lay in doc.get('layers', []) if lay.get('name') == name]
    if len(found) != 1:
        raise LevelError(f'{where}: needs exactly one layer "{name}", found {len(found)}')
    if found[0].get('type') != kind:
        raise LevelError(f'{where}, layer "{name}": is a {found[0].get("type")}, not a {kind}')
    return found[0]


def screens_tileset(doc: dict, where: str) -> int:
    sets = doc.get('tilesets', [])
    ours = [t for t in sets if 'skystrike_screens' in (t.get('name', '') + t.get('source', ''))]
    if len(ours) != 1:
        raise LevelError(f'{where}: needs the one "skystrike_screens" tileset, found {len(ours)}')
    return ours[0]['firstgid']


def world(doc: dict, where: str) -> list[int]:
    lay = find_layer(doc, WORLD_LAYER, 'tilelayer', where)
    at = f'{where}, layer "{WORLD_LAYER}"'
    if (lay.get('width'), lay.get('height')) != (WORLD_LEN, 1):
        raise LevelError(f'{at}: is {lay.get("width")}x{lay.get("height")}, the world is {WORLD_LEN}x1')
    first = screens_tileset(doc, where)
    out = []
    for sx, gid in enumerate(layer_data(lay, at)):
        if gid & FLIP_BITS:
            raise LevelError(f'{at}, screen {sx}: the tile is flipped or rotated')
        if gid < first:
            raise LevelError(f'{at}, screen {sx}: empty (every screen needs a type)')
        out.append(gid - first)
    return out


def marker_screen(o: dict, where: str) -> int:
    if o.get('rotation', 0):
        raise LevelError(f'{where}: is rotated')
    cx = o['x'] + (o.get('width') or 0) / 2
    sx = int(cx // TILE_W)
    if not 0 <= sx < WORLD_LEN or not -TILE_H <= o['y'] <= 2 * TILE_H:
        raise LevelError(f'{where}: at x {o["x"]}, y {o["y"]} is off the world strip')
    return sx


def markers(doc: dict, where: str) -> dict:
    lay = find_layer(doc, MISSION_LAYER, 'objectgroup', where)
    found: dict[str, int] = {}
    for o in lay.get('objects', []):
        kind = o.get('type') or o.get('class') or o.get('name', '')
        at = f'{where}, layer "{MISSION_LAYER}", object {o.get("id")} "{kind}"'
        if kind not in MARKERS:
            raise LevelError(f'{at}: unknown; the layer holds only {" and ".join(MARKERS)}')
        if kind in found:
            raise LevelError(f'{at}: a second {kind} marker')
        if o.get('gid') and o['gid'] != MARKER_GID[kind]:
            raise LevelError(f'{at}: shows tile gid {o["gid"]}, the {kind} marker is {MARKER_GID[kind]}')
        found[kind] = marker_screen(o, at)
        if found[kind] == 0:
            raise LevelError(f'{at}: screen 0 cannot be marked (0 means "none" in the record)')
    return found


def from_map(doc: dict, where: str) -> tuple[int, Mission, list[int]]:
    if (doc.get('tilewidth'), doc.get('tileheight')) != (TILE_W, TILE_H):
        raise LevelError(f'{where}: tiles are {doc.get("tilewidth")}x{doc.get("tileheight")}, not {TILE_W}x{TILE_H}')
    props = properties(doc, where)
    missing, extra = PROPS - props.keys(), props.keys() - PROPS
    if missing or extra:
        raise LevelError(f'{where}: map properties missing {sorted(missing)}, unknown {sorted(extra)}')
    if not isinstance(props['briefing'], str):
        raise LevelError(f'{where}: property "briefing" is not a string')
    marks = markers(doc, where)
    vals = {f: as_int(props[f], f'{where}: property "{f}"') for f in FIELDS}
    m = Mission(check_briefing(props['briefing'], where), marks.get('target', 0),
                marks.get('start', 0), **vals)
    check_mission(m, where)
    tiles = world(doc, where)
    check_world(tiles, f'{where}, layer "{WORLD_LAYER}"')
    if m.strtx and tiles[m.strtx] != 1:  # 1667: sx = strtx / 10 * 10, the plane parked on its runway
        raise LevelError(f'{where}, layer "{MISSION_LAYER}", start marker on screen {m.strtx}: '
                         f'the mission starts on an airfield: put it on a type 1 screen')
    return as_int(props['record'], f'{where}: property "record"'), m, tiles
