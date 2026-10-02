"""CRC32s of the menu's checked regions in the Hatari dumps (hatari/menu_it*.bin), for menu_test.zig."""
import os
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REGIONS = (('a', 0x6D800, 32000), ('b', 0x78000, 32000), ('phases', 0x29CA, 22), ('walkers', 0x2F68, 0x78),
           ('ring', 0x2D92, 0x6C), ('scroll', 0x16F6, 0x22), ('bufs', 0x38C4, 0x4100), ('lists', 0x3818, 0x34))

for it in (0, 99, 530, 999):
    d = open(os.path.join(HERE, 'hatari', f'menu_it{it}.bin'), 'rb').read()
    vals = ', '.join(f'.{n} = 0x{zlib.crc32(d[a:a + k]):08x}' for n, a, k in REGIONS)
    print(f'    .{{ .it = {it}, {vals} }},')
