#!/usr/bin/env python3
"""Cut sw_player.bin out of SID-Wizard 1.97's editor program (WTFPL, Hermit).

The editor PRG is the upstream 64tass build (SID-Wizard.cmp unpacked, or assembled from
SID-Wizard-1.97-sources-examples/native/sources with
  64tass -C -a -DEMULATOR=1 -DTUI_ONLY=0 -DOSCILLOSCOPE_SHOWS_ALL_CHANNELS=1 -D SID_AMOUNT=1 -D SWversion="'1.9'" editor.asm
which is byte-identical). Only what the 6502 player needs is kept: the player + playadapter code
($1000..$1CFF), the playadapter variables ($C679..$C6A8) and the cut-off meter byte ($AF5E).
  usage: sidwizard_z_player.py <editor.prg> <out sw_player.bin>
Format: repeated [u16 addr][u16 len][bytes], little endian."""
import struct, sys

BLOCKS = [(0x1000, 0xD00), (0xC679, 0x30), (0xAF5E, 2)]

def main(src: str, dst: str) -> None:
    prg = open(src, "rb").read()
    load = prg[0] | prg[1] << 8
    mem = {load + i: b for i, b in enumerate(prg[2:])}
    out = bytearray()
    for addr, n in BLOCKS:
        out += struct.pack("<HH", addr, n) + bytes(mem.get(addr + i, 0) for i in range(n))
    open(dst, "wb").write(out)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
