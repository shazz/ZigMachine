"""`levels.py check`, the build gate: the round trip is byte-exact, the committed
maps are the cart's built-in data, and the importer's refusals are proven (each
broken map below must raise LevelError naming its location; each legitimate
editor rewrite must import unchanged)."""
import base64
import copy
import json
import os
import tempfile
import zlib
from collections.abc import Callable

import levels
from levels_model import LevelError, decode_missions
from levels_parse import from_map


def _prop(doc: dict, name: str, value: object) -> dict:
    for p in doc['properties']:
        if p['name'] == name:
            p['value'] = value
    return doc


def _world(doc: dict, sx: int, gid: int) -> dict:
    doc['layers'][0]['data'][sx] = gid
    return doc


def _object(doc: dict, **kv: object) -> dict:
    doc['layers'][1]['objects'][0].update(kv)
    return doc


# (what, how to break a map, words the error must contain)
BROKEN: list[tuple[str, Callable[[dict], dict], tuple[str, ...]]] = [
    ('briefing line too long', lambda d: _prop(d, 'briefing', 'x' * 37), ('briefing line 1', '37')),
    ('nine briefing lines', lambda d: _prop(d, 'briefing', '\n'.join('a' * 9)), ('9 lines',)),
    ('non-ASCII briefing', lambda d: _prop(d, 'briefing', 'café'), ('line 1', 'printable')),
    ('mission out of range', lambda d: _prop(d, 'mission', 31), ('"mission"', '0..30')),
    ('bonus out of range', lambda d: _prop(d, 'bonus', 65536), ('"bonus"', '65535')),
    ('msb out of range', lambda d: _prop(d, 'msb', 17), ('"msb"', '0..16')),
    ('non-integer mfin', lambda d: _prop(d, 'mfin', 'lots'), ('"mfin"', 'not an integer')),
    ('unknown property', lambda d: d['properties'].append({'name': 'x', 'type': 'int', 'value': 1}) or d,
     ('unknown', "'x'")),
    ('missing property', lambda d: d.update(properties=d['properties'][1:]) or d, ('missing', 'record')),
    ('refused screen type 18', lambda d: _world(d, 30, 19), ('screen 30', 'type 18')),
    ('empty screen', lambda d: _world(d, 7, 0), ('screen 7', 'empty')),
    ('flipped tile', lambda d: _world(d, 5, 0x80000001), ('screen 5', 'flipped')),
    ('airfield off a base screen', lambda d: _world(d, 23, 2), ('screen 23', 'divisible by 10')),
    ('screen 0 not an airfield', lambda d: _world(d, 0, 10), ('screen 0', 'airfield')),
    ('screen 2 overwritten', lambda d: _world(d, 2, 21), ('screen 2', 'bridge')),
    ('marker off the strip', lambda d: _object(d, x=51 * 320 + 10), ('object 1', 'off the world')),
    ('marker on screen 0', lambda d: _object(d, x=10, width=20), ('screen 0 cannot',)),
    ('unknown object', lambda d: _object(d, type='tank', name='tank'), ('"tank"', 'unknown')),
    ('start off an airfield', lambda d: _object(d, type='start', name='start', gid=37),
     ('start marker on screen 44', 'airfield')),
    ('marker showing the wrong tile', lambda d: _object(d, gid=37), ('gid 37',)),
    ('world too short', lambda d: d['layers'][0].update(width=50) or d, ('50x1',)),
    ('no mission layer', lambda d: d.update(layers=d['layers'][:1]) or d, ('layer "mission"',)),
]


def _as_editors_rewrite(d: dict) -> dict:
    """Legitimate rewrites: old Tiled's property object, string ints, base64+zlib data, "class"."""
    d['properties'] = {p['name']: (str(p['value']) if p['type'] == 'int' else p['value'])
                       for p in d['properties']}
    lay = d['layers'][0]
    raw = b''.join(g.to_bytes(4, 'little') for g in lay.pop('data'))
    lay.update(encoding='base64', compression='zlib', data=base64.b64encode(zlib.compress(raw)).decode())
    for o in d['layers'][1]['objects']:
        o['class'] = o.pop('type')
    return d


def _as_webtiled_saves(d: dict) -> dict:
    """What WebTiled 1.6.0's File > Save wrote (measured: its IndexedDB "hello.json"): properties
    sorted by name, backgroundcolor "", "properties": [] on each layer, an object layer "color"
    "none", nextlayerid = the layer count, compressionlevel dropped."""
    d['properties'].sort(key=lambda p: p['name'])
    d.update(backgroundcolor='', nextlayerid=len(d['layers']))
    d.pop('compressionlevel', None)
    for lay in d['layers']:
        lay['properties'] = []
    d['layers'][1]['color'] = 'none'
    return d


def refusals(map_path: str) -> int:
    base = json.load(open(map_path, encoding='utf-8'))
    for what, breaker, words in BROKEN:
        try:
            from_map(breaker(copy.deepcopy(base)), 'm.json')
        except LevelError as e:
            missing = [w for w in words if w not in str(e)]
            if missing:
                raise LevelError(f'selftest "{what}": the error does not say {missing}: {e}') from e
            continue
        raise LevelError(f'selftest "{what}": the importer ACCEPTED it')
    for rewrite in (_as_editors_rewrite, _as_webtiled_saves):
        if from_map(rewrite(copy.deepcopy(base)), 'm.json') != from_map(base, 'm.json'):
            raise LevelError(f'selftest: a map after {rewrite.__name__} imports differently')
    return len(BROKEN)


def check() -> None:
    originals = {n: levels.read_file(levels.ASSETS, n) for n in levels.FILES}
    with tempfile.TemporaryDirectory() as tmp:
        levels.export(levels.ASSETS, tmp)
        again = levels.load([tmp])
    for n in levels.FILES:
        if again[n] != originals[n]:
            raise LevelError(f'round trip: import(export({n})) differs from the original')
    built = levels.load([levels.LEVELS])
    for n in levels.FILES:
        if built[n] != originals[n]:
            raise LevelError(f'{levels.LEVELS}: the maps import to a {n} that is not the cart\'s built-in '
                             f'one (run: levels.py import {levels.LEVELS} --cart)')
    count = refusals(os.path.join(levels.LEVELS, 'mission02.json'))
    print(f'levels: round trip byte-exact ({", ".join(f"{n} {len(originals[n])} B" for n in levels.FILES)}); '
          f'{len(decode_missions(originals["MISSIONS.DAT"]))} committed maps = the cart\'s data; '
          f'{count} broken maps refused')
