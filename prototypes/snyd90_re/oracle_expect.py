"""oracle_expect.py PART: CRC32s of a part's memory on the Musashi oracle after N VBLs, for *_test.zig.

PART f2: entry dump hatari/f2_entry.bin; set-up exec $1174..$15EC; a VBL = irq $162E + exec $1600..$161A.
Regions: everything the port keeps -- [$1000,$7FD00) minus the music ($8836..$AF16), the VBL flag
($1646..$1650) and the screens, which are CRC'd separately; the palette from the register file.
Also writes oracle/<part>_init.bin (the asset) and oracle/<part>_fN.bin.
"""
import os
import struct
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PARTS = {
    'f2': dict(entry='hatari/f2_entry.bin', setup='exec:1174:15ec', vbl='162e', body='1600:161a',
               holes=((0x8836, 0xAF16), (0x1646, 0x1650)), screens=(0x70000, 0x78000)),
}
FRAMES = (1, 2, 3, 50, 193, 700, 1500)


def run(p: dict, name: str) -> None:
    cmds = [p['setup'], f'dump:oracle/{name}_init.bin']
    done = 0
    for n in FRAMES:
        cmds += [f'loop:{n - done}:vbl:{p["vbl"]}:exec:{p["body"]}', f'dump:oracle/{name}_f{n}.bin',
                 f'hw:oracle/{name}_f{n}_hw.bin']
        done = n
    subprocess.run(['./m68run', p['entry'], '/dev/null'] + cmds, cwd=HERE, check=True, capture_output=True)


def crc_regions(d: bytes, p: dict) -> tuple[int, int, int]:
    keep = bytearray(d[0x1000:0x70000])
    for lo, hi in p['holes']:
        keep[lo - 0x1000:hi - 0x1000] = bytes(hi - lo)
    a, b = p['screens']
    return zlib.crc32(keep), zlib.crc32(d[a:a + 32000]), zlib.crc32(d[b:b + 32000])


def main() -> None:
    name = sys.argv[1]
    p = PARTS[name]
    os.makedirs(os.path.join(HERE, 'oracle'), exist_ok=True)
    run(p, name)
    for n in FRAMES:
        d = open(os.path.join(HERE, 'oracle', f'{name}_f{n}.bin'), 'rb').read()
        hw = open(os.path.join(HERE, 'oracle', f'{name}_f{n}_hw.bin'), 'rb').read()
        mem, a, b = crc_regions(d, p)
        pal = struct.unpack('>16H', hw[0x240:0x260])
        print(f'    .{{ .vbl = {n}, .mem = 0x{mem:08x}, .a = 0x{a:08x}, .b = 0x{b:08x}, '
              f'.pal = 0x{zlib.crc32(struct.pack(">16H", *pal)):08x} }},')


if __name__ == '__main__':
    main()
