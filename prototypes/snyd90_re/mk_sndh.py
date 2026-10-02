"""Wrap a position-independent replay rip into an SNDH, hand-assembled.

    mk_sndh.py BLOB OUT INIT_OFF PLAY_OFF TITLE TC [SUBTUNES [D0_FROM]]

INIT_OFF / PLAY_OFF are byte offsets into BLOB of the replay's own init (entered
with d0 = subtune, as SNDH passes it) and play entry points. exit silences the
three volume registers. D0_FROM (default 1) is the d0 the part itself passes for
subtune 1: 0 inserts `subq.w #1,d0` before the init. The composer is $COMM (default Mad Max).
"""
import os
import struct
import sys

blob = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
init_off = int(sys.argv[3], 0)
play_off = int(sys.argv[4], 0)
title = sys.argv[5]
tc = sys.argv[6]
subs = int(sys.argv[7]) if len(sys.argv) > 7 else 1
d0_from = int(sys.argv[8]) if len(sys.argv) > 8 else 1

hdr = bytearray()
hdr += b'\x60\x00\x00\x00' * 3  # bra.w init / exit / play, patched below
hdr += b'SNDH'
for tag in (b'TITL' + title.encode() + b'\0', b'COMM' + os.environ.get('COMM', 'Mad Max').encode() + b'\0',
            b'RIPPripped from the Swedish New Year Demo disk (SNYD_90.MSA)\0',
            b'YEAR1990\0', b'##%02d\0' % subs, b'TC' + tc.encode() + b'\0'):
    hdr += tag
if len(hdr) & 1:
    hdr += b'\0'
hdr += b'HDNS'
init_at = len(hdr)
if d0_from == 0:
    hdr += b'\x53\x40'  # subq.w #1,d0: the part's own d0
init_bra = len(hdr)
hdr += b'\x60\x00\x00\x00'  # init: bra.w blob+init_off
exit_at = len(hdr)
for reg in (8, 9, 10):
    hdr += struct.pack('>HHH', 0x11FC, reg, 0x8800)  # move.b #reg,$ffff8800.w
    hdr += struct.pack('>HHH', 0x11FC, 0, 0x8802)  # move.b #0,$ffff8802.w
hdr += b'\x4e\x75'  # rts
play_at = len(hdr)
hdr += b'\x60\x00\x00\x00'  # play: bra.w blob+play_off
blob_at = len(hdr)


def bra(at, target):
    d = target - (at + 2)
    assert -32768 <= d < 32768
    hdr[at + 2:at + 4] = struct.pack('>h', d)


bra(0, init_at)
bra(4, exit_at)
bra(8, play_at)
bra(init_bra, blob_at + init_off)
bra(play_at, blob_at + play_off)
open(out, 'wb').write(bytes(hdr) + blob)
print(out, len(hdr) + len(blob))
