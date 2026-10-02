"""SNYD 90: list the loader's part table ($CA8, 18-byte entries) and rip every part.

Entry: start.w (linear sector on its side: track = start/10, sector = start%10+1),
count.w (sectors), side.w (0/1), load.l, packed.l (0 = stored), entry.l.
The FDC loader reads `count` sectors on ONE side, track after track.
Packed parts go through $7D8 (ByteKiller) then $8C8 (word-run pass); see depack.py.
"""
import os
import struct
import sys

from depack import bytekiller, wordruns

HERE = os.path.dirname(os.path.abspath(__file__))
img = open(os.path.join(HERE, 'SNYD_90.ST'), 'rb').read()
ldr = open(os.path.join(HERE, 'loader600.bin'), 'rb').read()
SPT = 10


def read_side(start: int, count: int, side: int) -> bytes:
    out = bytearray()
    for n in range(start, start + count):
        trk, sec = divmod(n, SPT)
        off = ((trk * 2 + side) * SPT + sec) * 512
        out += img[off:off + 512]
    return bytes(out)


def table() -> list[tuple[int, ...]]:
    rows = []
    for i in range(16):
        o = 0xCA8 - 0x600 + i * 18
        row = struct.unpack('>HHHIII', ldr[o:o + 18])
        if row[1] == 0 or row[1] > 1600:
            break
        rows.append(row)
    return rows


def main() -> None:
    os.makedirs(os.path.join(HERE, 'parts'), exist_ok=True)
    for i, (start, cnt, side, load, packed, entry) in enumerate(table()):
        raw = read_side(start, cnt, side)
        print(f'{i:2d}: start {start:4d} (trk {start // SPT:2d} s{start % SPT + 1}) '
              f'cnt {cnt:4d} side {side} load ${load:06x} packed ${packed:06x} '
              f'entry ${entry:06x}', end='')
        data = raw
        if packed:
            data = wordruns(bytekiller(raw[:packed]))
            print(f' -> {len(data)} B', end='')
        print()
        open(os.path.join(HERE, 'parts', f'p{i}_{load:06x}.bin'), 'wb').write(data)


if __name__ == '__main__' and len(sys.argv) == 1:
    main()
