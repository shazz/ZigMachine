#!/usr/bin/env python3
"""SKYSTRIKE: the headless harness's reference, from the ORIGINAL program run on Hatari.

    python3 tools/skystrike/make_fixture.py

Source: prototypes/skystrike_re/hatari/ (gitignored; SKYSTRIKE_RE overrides): RAM dumps of the
compiled game (STRVAP, run from a floppy with its Evapour loader, TOS 1.02, ST, 1 MB) taken at
title_ram.bin (the title's scroller), difficulty_ram.bin (the menu), mission_ram.bin (mission 1's
briefing), game_start_ram.bin (the first frame of play), crashland_ram.bin (cl = 1 poked at the
start: "You Managed to Crash Land !" boxed) and hiscore_ram.bin (the title's timeout: the hall of
fame, its APPEAR finished); and hatari.log, the per-pass trace of the variables at line 128 (a
:trace breakpoint dumping $405C0-$4065F) after th = 9 was poked at the start of play.

Writes apps/skystrike_fixture.json:
  screens   name, the screen (physic $F8000 / back $F0000), the rows compared (all 320 columns;
            the rows under the flag, the planes and the scroller's latest letter are left out:
            those are sprites or the moment), the reference indices (zlib + base64)
  takeoff   per pass: x, y, r, sp# x 1000 (truncated), fuel
"""
import base64
import json
import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('SKYSTRIKE_RE', os.path.join(ROOT, 'prototypes', 'skystrike_re'))
sys.path.insert(0, os.path.join(RE, 'tools'))

from stscr import screen  # noqa: E402  (the RE tools directory, added above)
import trace_vars  # noqa: E402

OUT = os.path.join(ROOT, 'apps', 'skystrike_fixture.json')
PHYSIC, BACK = 0xF8000, 0xF0000
# (name, dump, screen, [(first row, last row + 1), ...])
SCREENS = [
    ('title back', 'title_ram', BACK, [(0, 40), (48, 200)]),
    ('menu back', 'difficulty_ram', BACK, [(0, 200)]),
    ('menu physic', 'difficulty_ram', PHYSIC, [(0, 110)]),
    ('briefing back', 'mission_ram', BACK, [(0, 200)]),
    ('briefing physic', 'mission_ram', PHYSIC, [(0, 110)]),
    ('play back', 'game_start_ram', BACK, [(0, 200)]),
    ('play physic', 'game_start_ram', PHYSIC, [(0, 100), (176, 200)]),
    ('crash-land physic', 'crashland_ram', PHYSIC, [(0, 200)]),
    ('crash-land back', 'crashland_ram', BACK, [(0, 200)]),
    ('hall of fame physic', 'hiscore_ram', PHYSIC, [(0, 200)]),
]


def region(rows: list[list[int]], spans: list[tuple[int, int]]) -> bytes:
    return bytes(v for a, b in spans for y in range(a, b) for v in rows[y])


def main() -> None:
    out = {'screens': [], 'takeoff': []}
    for name, dump, addr, spans in SCREENS:
        ram = open(os.path.join(RE, 'hatari', dump + '.bin'), 'rb').read()
        data = region(screen(ram, addr), spans)
        out['screens'].append({'name': name, 'screen': 'physic' if addr == PHYSIC else 'back',
                               'spans': spans, 'z': base64.b64encode(zlib.compress(data, 9)).decode()})
    for d in trace_vars.rows(os.path.join(RE, 'hatari', 'hatari.log')):
        out['takeoff'].append([d['x'], d['y'], d['r'], int(d['sp'] * 1000), d['fuel']])
    json.dump(out, open(OUT, 'w'), separators=(',', ':'))
    print(f'{OUT}: {len(out["screens"])} screens, {len(out["takeoff"])} passes, {os.path.getsize(OUT)} bytes')


if __name__ == '__main__':
    main()
