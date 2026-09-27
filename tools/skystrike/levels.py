#!/usr/bin/env python3
"""SKYSTRIKE (cart 79) levels <-> Tiled JSON maps, for editing in WebTiled or Tiled.

    python3 tools/skystrike/levels.py export [--data DIR] [--out DIR]
        MISSIONS.DAT + SCRNDATA.DAT -> missionNN.json, one map per record, and
        the tileset PNG next to them (render it first: render_tileset.mjs)
    python3 tools/skystrike/levels.py import MAP_OR_DIR... (--out DIR | --cart)
        the maps -> MISSIONS.DAT + SCRNDATA.DAT (--cart: into the cart's own
        assets, lower-case, as the build embeds them). Validates everything.
    python3 tools/skystrike/levels.py sync-world MAP [DIR]
        copy MAP's world layer into every other map of DIR (the world is shared)
    python3 tools/skystrike/levels.py disk MAP_OR_DIR... --out my.zmd
        the maps -> a SKYSTRIKE disk carrying them (drop it on the ZigMachine page)
    python3 tools/skystrike/levels.py check
        the gate: import(export(original)) == original, and the committed maps
        import to exactly the cart's built-in files, and the importer refuses
        every broken map in levels_check.py

The data model and the rules: docs/ports/SKYSTRIKE_LEVELS.md.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from levels_model import (LevelError, check_set, check_world, decode_missions,  # noqa: E402
                          encode_missions)
from levels_parse import from_map, world  # noqa: E402
from levels_tiled import MARKERS_PNG, TILESET_PNG, WORLD_LAYER, to_map  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ASSETS = os.path.join(ROOT, 'apps', 'zig', 'assets', 'screens', 'skystrike')
LEVELS = os.path.join(ASSETS, 'levels')
FILES = ('MISSIONS.DAT', 'SCRNDATA.DAT')


def read_file(d: str, name: str) -> bytes:
    for n in (name, name.lower()):
        if os.path.exists(os.path.join(d, n)):
            return open(os.path.join(d, n), 'rb').read()
    raise LevelError(f'{d}: no {name}')


def write_json(path: str, doc: dict) -> None:
    """Indented, but each list of numbers (the world strip) on one line."""
    text = json.dumps(doc, indent=1)
    text = re.sub(r'\[(\s*-?\d+,?)+\s*\]', lambda m: re.sub(r'\s+', '', m.group(0)), text)
    with open(path, 'w') as f:
        f.write(text + '\n')


def read_png(name: str) -> bytes:
    path = os.path.join(LEVELS, name)
    if not os.path.exists(path):
        raise LevelError(f'no {path}: run node tools/skystrike/render_tileset.mjs after a build')
    return open(path, 'rb').read()


def export(data: str, out: str) -> list[str]:
    missions = decode_missions(read_file(data, 'MISSIONS.DAT'))
    raw_world = read_file(data, 'SCRNDATA.DAT')
    check_world(list(raw_world), 'SCRNDATA.DAT')
    pngs = tuple(read_png(n) for n in (TILESET_PNG, MARKERS_PNG))
    os.makedirs(out, exist_ok=True)
    if os.path.abspath(out) != os.path.abspath(LEVELS):
        for name, data in zip((TILESET_PNG, MARKERS_PNG), pngs, strict=True):
            open(os.path.join(out, name), 'wb').write(data)
    names = []
    for n, m in enumerate(missions, 1):
        name = os.path.join(out, f'mission{n:02d}.json')
        write_json(name, to_map(n, m, raw_world, pngs))
        names.append(name)
    return names


def map_files(args: list[str]) -> list[str]:
    out = []
    for a in args:
        if os.path.isdir(a):
            out += sorted(os.path.join(a, n) for n in os.listdir(a) if n.endswith('.json'))
        else:
            out.append(a)
    if not out:
        raise LevelError(f'no .json maps in {args}')
    return out


def load(paths: list[str]) -> dict[str, bytes]:
    records, worlds = {}, {}
    for p in map_files(paths):
        where = os.path.basename(p)
        try:
            doc = json.load(open(p, encoding='utf-8'))
        except json.JSONDecodeError as e:
            raise LevelError(f'{where}: not JSON: {e}') from e
        n, m, w = from_map(doc, where)
        if n in records:
            raise LevelError(f'{where}: record {n} is also {records[n][0]}')
        records[n], worlds[where] = (where, m), w
    want = list(range(1, len(records) + 1))
    if sorted(records) != want:
        raise LevelError(f'records {sorted(records)}: must be 1..{len(records)}, no gaps')
    check_same_world(worlds)
    missions = [records[n][1] for n in want]
    check_set(missions)
    first = next(iter(worlds))
    return {'MISSIONS.DAT': encode_missions(missions),
            'SCRNDATA.DAT': check_world(worlds[first], f'{first}, layer "{WORLD_LAYER}"')}


def check_same_world(worlds: dict[str, list[int]]) -> None:
    (first, ref), *rest = worlds.items()
    for where, w in rest:
        diff = [sx for sx in range(len(ref)) if w[sx] != ref[sx]]
        if diff:
            raise LevelError(f'{where}, layer "{WORLD_LAYER}", screen {diff[0]}: type {w[diff[0]]}, but '
                             f'{first} has {ref[diff[0]]}; the world is shared by every mission '
                             f'(run: levels.py sync-world <the map you edited>)')


def note_unreachable(missions_dat: bytes) -> None:
    """Records after the first ending (mission 8, 1690) are valid but never briefed."""
    ms = decode_missions(missions_dat)
    end = next(n for n, m in enumerate(ms, 1) if m.mission == 8)
    if end < len(ms):
        print(f'note: records {end + 1}-{len(ms)} come after the ending (record {end}, mission 8) '
              f'and are never played', file=sys.stderr)


def write(files: dict[str, bytes], out: str, lower: bool) -> None:
    os.makedirs(out, exist_ok=True)
    for name, data in files.items():
        open(os.path.join(out, name.lower() if lower else name), 'wb').write(data)
        print(f'{name:13s} {len(data):5d} bytes -> {out}')


def sync_world(src: str, d: str) -> None:
    ref = json.load(open(src, encoding='utf-8'))
    tiles = world(ref, os.path.basename(src))
    for p in map_files([d]):
        if os.path.abspath(p) == os.path.abspath(src):
            continue
        doc = json.load(open(p, encoding='utf-8'))
        lay = next(lay for lay in doc['layers'] if lay.get('name') == WORLD_LAYER)
        first = next(t['firstgid'] for t in doc['tilesets'] if 'skystrike_screens' in t.get('name', ''))
        lay.pop('encoding', None), lay.pop('compression', None)
        lay['data'] = [t + first for t in tiles]
        write_json(p, doc)
        print(f'{os.path.basename(p)}: world = {os.path.basename(src)}\'s')


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    e = sub.add_parser('export')
    e.add_argument('--data', default=ASSETS)
    e.add_argument('--out', default=LEVELS)
    i = sub.add_parser('import')
    i.add_argument('maps', nargs='+')
    g = i.add_mutually_exclusive_group(required=True)
    g.add_argument('--out')
    g.add_argument('--cart', action='store_true')
    s = sub.add_parser('sync-world')
    s.add_argument('map')
    s.add_argument('dir', nargs='?', default=LEVELS)
    d = sub.add_parser('disk')
    d.add_argument('maps', nargs='+')
    d.add_argument('--out', required=True, help='the .zmd to write')
    d.add_argument('--title', default='SKYSTRIKE custom missions')
    sub.add_parser('check')
    a = ap.parse_args()
    try:
        if a.cmd == 'export':
            print('\n'.join(export(a.data, a.out)))
        elif a.cmd == 'import':
            files = load(a.maps)
            note_unreachable(files['MISSIONS.DAT'])
            write(files, ASSETS if a.cart else a.out, a.cart)
        elif a.cmd == 'sync-world':
            sync_world(a.map, a.dir)
        elif a.cmd == 'disk':
            from levels_disk import make_disk
            files = load(a.maps)
            note_unreachable(files['MISSIONS.DAT'])
            make_disk(files, a.out, a.title)
        else:
            from levels_check import check
            check()
    except LevelError as err:
        sys.exit(f'levels.py {a.cmd}: FAILED: {err}')


if __name__ == '__main__':
    main()
