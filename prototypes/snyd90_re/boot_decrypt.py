"""Decrypt SNYD 90's stage-2 loader: track 0 side 0 sectors 2..5 -> $600.

plain[i] = cipher[i] ^ key[i]; key[0] = d1 (SR and $FFE0 packed), key[i+1] = plain[i].
SR after `cmpa.l #$7000,a2` with the boot buffer below $7000 is $2709 (N,C set).
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
img = open(os.path.join(HERE, 'SNYD_90.ST'), 'rb').read()
src = img[512:512 + 2048]
key = int(sys.argv[1], 16) if len(sys.argv) > 1 else 0x2709FFE0
out = bytearray()
for i in range(0, len(src), 4):
    c = struct.unpack('>I', src[i:i + 4])[0]
    p = c ^ key
    out += struct.pack('>I', p)
    key = p
open(os.path.join(HERE, 'loader600.bin'), 'wb').write(out)
