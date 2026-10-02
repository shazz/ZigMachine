"""Locate every Mad Max 'TFMX' (Hippel) music block in each binary, size it from
its header the way the replay's init does, and search the SNDH archive for it.

Size rule (replay init at menu 0x3bc52):
  a1 = data+0x20 + (w4+1)*64 + (w6+1)*64 + (w8+1)*wC + (wA+1)*12  -> song table
  song table: (w10+1)*6 bytes; whatever follows is the end of the TFMX block.
"""
import glob
import struct
import sys

from load import files

ARCH = '/home/matt/projects/ZigMachine/prototypes/sndh_lf'


def blocks(d):
    i = d.find(b'TFMX')
    while i >= 0:
        w = struct.unpack('>9H', d[i + 4:i + 22])
        # header word offsets relative to block: 4,6,8,a,c,e,10 -> w[0..6]
        w4, w6, w8, wa, wc, we, w10 = w[0], w[1], w[2], w[3], w[4], w[5], w[6]
        n = 0x20 + (w4 + 1) * 64 + (w6 + 1) * 64 + (w8 + 1) * wc + (wa + 1) * 12 + (w10 + 1) * 6
        yield i, n, w
        i = d.find(b'TFMX', i + 4)


if __name__ == '__main__':
    arch = {p: open(p, 'rb').read() for p in glob.glob(f'{ARCH}/**/*.sndh', recursive=True)}
    for k, d in files().items():
        for i, n, w in blocks(d):
            blk = d[i:i + n]
            print(f'{k}: TFMX at 0x{i:x} len 0x{n:x} hdr {w}')
            for p, a in arch.items():
                j = a.find(blk[:256])
                if j >= 0:
                    full = a[j:j + n] == blk
                    print(f'    {"FULL" if full else "head"} match {p[len(ARCH)+1:]} @0x{j:x}')
