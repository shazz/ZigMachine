"""SKYSTRIKE levels -> Tiled JSON maps (the subset WebTiled 1.6.0 and desktop Tiled both read).

One map per MISSIONS.DAT record:
  tile layer "world"     51 x 1, one tile per screen; tile id = the screen type
  object layer "mission" a "start" and a "target" marker (tile objects), each on a screen
  map properties         record, mission, misf, mfin, bonus, msb, meb, briefing
The world strip is the SAME in every map (the game has one world: 2500).

WebTiled's decoder (justgook/elm-tiled 3.0.2) fails the WHOLE map on: a string
"version", an object without "type" or "rotation", properties not in the
[{name, type, value}] list form; and it draws only tile objects. So the maps
carry exactly those shapes, and both tilesets are embedded with a bare image
name (WebTiled matches a dropped file by name).
"""
import struct

from levels_model import LevelError, Mission, SCREEN_TYPES, WORLD_LEN

TILE_W, TILE_H = 320, 176          # a screen above the panel: 320 x 176 (1004's bar 0,0 to 319,175)
COLUMNS, TILECOUNT = 6, 36         # tile id n = screen type n; 18 and 19 are drawn as refused
TILESET_PNG = 'skystrike_screens.png'
MARKERS_PNG = 'skystrike_markers.png'
MARK_W = 64                        # marker tiles: 64 x 64, sprite 1 (the Spitfire) and 119 (TGT)
MARKERS = ('start', 'target')      # tile ids 0, 1 of the markers tileset
MARKER_GID = {k: 1 + TILECOUNT + i for i, k in enumerate(MARKERS)}
MARKER_Y = {'start': 72, 'target': 168}  # a tile object's y is its bottom edge
WORLD_LAYER, MISSION_LAYER = 'world', 'mission'
FIELDS = ('mission', 'misf', 'mfin', 'bonus', 'msb', 'meb')


def png_size(data: bytes, name: str) -> tuple[int, int]:
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise LevelError(f'{name}: not a PNG')
    return struct.unpack('>II', data[16:24])


def embedded(name: str, png: bytes, first: int, tw: int, th: int, columns: int, count: int,
             labels: list[str]) -> dict:
    w, h = png_size(png, name)
    if (w, h) != (columns * tw, -(-count // columns) * th):
        raise LevelError(f'{name}: {w}x{h} is not {columns} x {count} tiles of {tw}x{th}: re-render it')
    tiles = [{'id': t, 'properties': [prop('is', label)]} for t, label in enumerate(labels)]
    return {'firstgid': first, 'name': name.removesuffix('.png'), 'image': name, 'imagewidth': w,
            'imageheight': h, 'tilewidth': tw, 'tileheight': th, 'tilecount': count,
            'columns': columns, 'margin': 0, 'spacing': 0, 'tiles': tiles}


def tilesets(screens_png: bytes, markers_png: bytes) -> list[dict]:
    names = [f'screen type {t}: {SCREEN_TYPES.get(t, "REFUSED, the game draws nothing")}'
             for t in range(TILECOUNT)]
    return [embedded(TILESET_PNG, screens_png, 1, TILE_W, TILE_H, COLUMNS, TILECOUNT, names),
            embedded(MARKERS_PNG, markers_png, 1 + TILECOUNT, MARK_W, MARK_W, len(MARKERS),
                     len(MARKERS), [f'{k} marker' for k in MARKERS])]


def prop(name: str, value: object) -> dict:
    kind = 'string' if isinstance(value, str) else 'int'
    return {'name': name, 'type': kind, 'value': value}


def marker(oid: int, kind: str, screen: int) -> dict:
    return {'id': oid, 'gid': MARKER_GID[kind], 'name': kind, 'type': kind,
            'x': screen * TILE_W + (TILE_W - MARK_W) // 2, 'y': MARKER_Y[kind],
            'width': MARK_W, 'height': MARK_W, 'rotation': 0, 'visible': True}


def layers(m: Mission, world: bytes) -> list[dict]:
    objects = []
    for kind, screen in (('start', m.strtx), ('target', m.tgtx)):
        if screen:  # 0 = none: 1667 keeps the current screen, 118 shows no arrow
            objects.append(marker(len(objects) + 1, kind, screen))
    return [{'id': 1, 'name': WORLD_LAYER, 'type': 'tilelayer', 'x': 0, 'y': 0, 'width': WORLD_LEN,
             'height': 1, 'opacity': 1, 'visible': True, 'data': [t + 1 for t in world]},
            {'id': 2, 'name': MISSION_LAYER, 'type': 'objectgroup', 'x': 0, 'y': 0, 'opacity': 1,
             'visible': True, 'draworder': 'topdown', 'objects': objects}]


def to_map(n: int, m: Mission, world: bytes, pngs: tuple[bytes, bytes]) -> dict:
    """Record n (1-based) as a Tiled map."""
    props = [prop('record', n)] + [prop(f, getattr(m, f)) for f in FIELDS]
    props.append(prop('briefing', '\n'.join(m.briefing).rstrip('\n')))
    lays = layers(m, world)
    return {'type': 'map', 'version': 1.2, 'tiledversion': '1.2.0', 'orientation': 'orthogonal',
            'renderorder': 'right-down', 'infinite': False,
            'width': WORLD_LEN, 'height': 1, 'tilewidth': TILE_W, 'tileheight': TILE_H,
            'nextlayerid': 3, 'nextobjectid': len(lays[1]['objects']) + 1, 'properties': props,
            'layers': lays, 'tilesets': tilesets(*pngs)}
