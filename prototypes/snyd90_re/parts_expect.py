"""parts_expect.py PART: CRC32s of a best-effort part's memory on the Musashi oracle, for fN_test.zig.

From the part's asset state (mk_parts.py's run, redone here), N frames of the ORIGINAL code:
  (f3_test.zig's CRCs came from the same run by hand: irq $1888E + exec $1810A..$180FA)
  f4: irq VBL $F2BE, then the main loop's body exec $F1B8..$F274
  f6: irq VBL $127FE each VBL, and every second one the main loop's body exec $129FE..$12A3C
  f5: irq VBL $17D42, the main loop's body exec $17EDC..$17ED2, then call $15A68 -- the
      fullscreen routine's own writes (texture + letter column) between its border switches
Regions: [BASE, $7FC00) (past it the oracle's own stack, $7FDxx) with HOLES read as zeros.
M68RUN as mk_parts.py.
"""
import os
import subprocess
import sys
import tempfile
import zlib

from mk_parts import M68RUN, PARTS, RE

FRAME = {
    'f4': ['irq:f2be', 'exec:f1b8:f274'],
    # ($1525E sets d0/d1 = 0/2 and a0/a1 = the shifter's $FF8260/$FF820A before $15A68)
    'f5': ['irq:17d42', 'exec:17edc:17ed2', 'reg:0:0', 'reg:1:2', 'reg:8:ff8260', 'reg:9:ff820a', 'call:15a68'],
}
# F6's main loop runs every second VBL: its counter $12AEC is 1 at the asset's point.
F6_VBL, F6_PASS = 'irq:127fe', 'exec:129fe:12a3c'


def f6_frames(n: int, count: int) -> tuple[list[str], int]:
    out = []
    for _ in range(n):
        out.append(F6_VBL)
        count += 1
        if count >= 2:
            out.append(F6_PASS)
            count = 0
    return out, count
# What the port does not keep: the stack, and for F4 the music ($17FC0.., the SNDH's) and
# the VBL flag ($F3EA).
HOLES = {'f4': [(0xF3EA, 0xF3EC), (0x17FC0, 0x1AEDC), (0x5F000, 0x60000)],
         'f5': [],
         # F6: the music's replay + state ($E50E..$ED08) and Timer B's raster pointer ($127FA)
         'f6': [(0xE50E, 0xED08), (0x127FA, 0x127FE)]}
SHOTS = (1, 5, 300, 1200)


def main() -> None:
    name = sys.argv[1]
    pc, phase, stop, base, extra = PARTS[name]
    with tempfile.TemporaryDirectory() as tmp:
        cmds = [*extra, 'sr:2700', f'rt:0:{pc:x}:{phase}:{stop:x}']
        done, count = 0, 1
        for n in SHOTS:
            if name == 'f6':
                more, count = f6_frames(n - done, count)
                cmds += more
            else:
                cmds += FRAME[name] * (n - done)
            cmds.append(f'dump:{tmp}/f{n}.bin')
            done = n
        subprocess.run([M68RUN, os.path.join(RE, 'hatari', f'{name}_entry.bin'), '/dev/null', *cmds],
                       check=True, capture_output=True)
        for n in SHOTS:
            d = bytearray(open(f'{tmp}/f{n}.bin', 'rb').read())
            for lo, hi in HOLES[name]:
                d[lo:hi] = bytes(hi - lo)
            print(f'    .{{ .vbl = {n}, .mem = 0x{zlib.crc32(d[base:0x7FC00]):08x} }},')


if __name__ == '__main__':
    main()
