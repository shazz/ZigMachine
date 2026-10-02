"""Write cart 83's assets (apps/zig/assets/screens/snyd_90/) from the ripped parts, byte for byte.

  menu.raw       part 0 as the loader leaves it at $1000 (71,680 B)
  intro_spu.raw  part 8's Spectrum 512 picture: screen $5724 + 199 line palettes $D424 (51,104 B)
Run parts.py first (it rips parts/ from SNYD_90.ST).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'apps', 'zig', 'assets', 'screens', 'snyd_90')


def part(name: str) -> bytes:
    return open(os.path.join(HERE, 'parts', name), 'rb').read()


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    menu = part('p0_001000.bin')
    intro = part('p8_001000.bin')[0x4724:0x4724 + 32000 + 199 * 96]
    assert len(menu) == 71680 and len(intro) == 51104
    for name, data in (('menu.raw', menu), ('intro_spu.raw', intro)):
        open(os.path.join(OUT, name), 'wb').write(data)
        print(name, len(data))


if __name__ == '__main__':
    main()
