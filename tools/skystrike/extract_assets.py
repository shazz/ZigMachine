#!/usr/bin/env python3
"""SKYSTRIKE (Shadow Software 1990, Automation Menu Disk 258): the cart's data, cut from the disk.

    python3 tools/skystrike/extract_assets.py

Source: prototypes/skystrike_re/ (gitignored; SKYSTRIKE_RE overrides), built from the menu disk
"Automation Menu Disk 258 (1990)(Automation)[a].st" by its tools/fat.py (the FAT), unauto.py
(STRVAP, AUTOMATION PACKER V2.3r, depacked by its own stub in em68 -> strike.prg, the compiled
STOS program) and unlsd.py (every SKYSTRKE\\ file is "LSD!"-packed and depacked on Fopen by the
Evapour loader STRIKE.VAP; unlsd.py runs that loader's own routine). See the RE README.

Writes, into apps/zig/assets/screens/skystrike/:
  skypic1.pac, skypic2.pac, hipic.pac, news.pac
                 the four pictures as STOS "pack"ed screens ($06071963), LSD-depacked: the cart
                 runs STOS's unpack on them (pac.zig), as the game's `unpack` does
  sprites.bnk    the sprite bank ($19861987, 123 low-res sprites + PALT), from strike.prg: the
                 COMPILED bank, which differs from the source's PKTSPRT.MBK in 367 bytes
  screens.bnk    bank 8, the screen-object table (s * 160 + a * 8), from strike.prg
  font.bin       STOS's 8x8 low-res font (8X8.CR0 glyphs $20-$FF, 8 bytes each), from strike.prg
  data.dat, missions.dat, scrndata.dat, spitfire.hsc   the game's files, LSD-depacked
  maestro.bin    the Maestro extension's volume table (256 x 16 bytes) + speed table (32 bytes),
                 MAESTRO.EXD $0DEA-$1E0A, for sound.s
  samples.bnk    bank 10, the Maestro sample bank ("MAESTRO!"), from strike.prg
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('SKYSTRIKE_RE', os.path.join(ROOT, 'prototypes', 'skystrike_re'))
OUT = os.path.join(ROOT, 'apps', 'zig', 'assets', 'screens', 'skystrike')
sys.path.insert(0, os.path.join(RE, 'tools'))

from unlsd import unlsd  # noqa: E402  (the RE tools directory, added above)

# Offsets in strike.prg (the depacked STRVAP, file offsets). Each is checked below.
SPRITES = (0x2E20A, 28802)
SCREENS = (0x35C0A, 4096)
SAMPLES = (0x36C0A, 7936)
FONT = (0x25786 + 0x108, 224 * 8)
MAESTRO_TABLES = (0xDEA, 0x1E0A)
LSD_FILES = ['SKYPIC1.PAC', 'SKYPIC2.PAC', 'HIPIC.PAC', 'NEWS.PAC',
             'DATA.DAT', 'MISSIONS.DAT', 'SCRNDATA.DAT', 'SPITFIRE.HSC']


def cut(prg: bytes, at: tuple[int, int], magic: bytes) -> bytes:
    b = prg[at[0]:at[0] + at[1]]
    assert b.startswith(magic), f'no {magic!r} at {at[0]:#x}'
    return b


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    prg = open(os.path.join(RE, 'strike.prg'), 'rb').read()
    out = {
        'sprites.bnk': cut(prg, SPRITES, b'\x19\x86\x19\x87'),
        'screens.bnk': prg[SCREENS[0]:SCREENS[0] + SCREENS[1]],
        'samples.bnk': cut(prg, SAMPLES, b'MAESTRO!'),
        'font.bin': prg[FONT[0]:FONT[0] + FONT[1]],
    }
    mbk = open(os.path.join(RE, 'bas', 'SKYSCRNS.MBK'), 'rb').read()[18:]
    assert out['screens.bnk'] == mbk, 'bank 8 is not SKYSCRNS.MBK'
    assert out['font.bin'][8:16] == bytes.fromhex('1818181818001800'), 'no "!" glyph'
    exd = open(os.path.join(RE, 'bas', 'MAESTRO.EXD'), 'rb').read()[28:]
    out['maestro.bin'] = exd[MAESTRO_TABLES[0]:MAESTRO_TABLES[1]]
    for name in LSD_FILES:
        raw = unlsd(open(os.path.join(RE, 'files', 'SKYSTRKE', name), 'rb').read())
        out[name.lower()] = raw
    for name, data in out.items():
        open(os.path.join(OUT, name), 'wb').write(data)
        print(f'{name:14s} {len(data):6d} bytes')


if __name__ == '__main__':
    main()
