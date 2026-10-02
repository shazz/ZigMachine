"""Rip each binary's Mad Max TFMX replay + data into an SNDH (via mk_sndh.py).

The replay is position independent and begins with three bra.w (init, ?, play);
find the triple nearest below the TFMX block, then wrap [triple, TFMX end).
"""
import subprocess
import struct

from load import files
from tfmx import blocks

TITLES = {'menu': 'Nitrowave - Battletec Menu', 'ric': 'Nitrowave - Multisprites',
          'bspr': 'Nitrowave - Big Sprite', 'dam': 'Nitrowave - Sapristi 3615 Gen 4'}


def find_header(d, tfmx_at):
    best = None
    for o in range(max(0, tfmx_at - 0x1000), tfmx_at, 2):
        if d[o:o + 2] == b'\x60\x00' and d[o + 4:o + 6] == b'\x60\x00' and d[o + 8:o + 10] == b'\x60\x00':
            best = o
    return best


for k, d in files().items():
    for i, n, w in blocks(d):
        h = find_header(d, i)
        tgt = [h + 2 + struct.unpack('>h', d[h + 2 + 4 * j:h + 4 + 4 * j])[0] + 4 * j for j in range(3)]
        print(f'{k}: header 0x{h:x} targets {[hex(t) for t in tgt]} tfmx 0x{i:x}+0x{n:x} songs {w[6] + 1}')
        blob = d[h:i + n + (0x1000 if k == "dam" else 0x100)]  # dam: init hard-codes song tables past the header size
        open(f'{k}_replay.bin', 'wb').write(blob)
        subprocess.run(['python3', 'mk_sndh.py', f'{k}_replay.bin', f'{k}_rip.sndh', '0', '8',
                        TITLES[k], '50', str(w[6] + 1)], check=True)
