"""Shared loaders for the NITROWAV.ST rip (disk/ is fatx.py's output)."""
import struct

BASE = __file__.rsplit('/', 1)[0]


def prg(path):
    d = open(path, 'rb').read()
    magic, text, data, bss = struct.unpack('>HIII', d[:14])
    assert magic == 0x601a
    return d[28:28 + text + data], text, data, bss


def files():
    m, _, _, _ = prg(f'{BASE}/disk/AUTO/MENU.PRG')
    return {
        'menu': m,
        'bspr': open(f'{BASE}/disk/B_SPRITE.BIN', 'rb').read(),
        'dam': open(f'{BASE}/disk/DAMIER3D.BIN', 'rb').read(),
        'ric': open(f'{BASE}/disk/DEMO_RIC.BIN', 'rb').read(),
    }
