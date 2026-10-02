"""parts_expect.py PART: CRC32s of a best-effort part's memory on the Musashi oracle, for fN_test.zig.

From the part's asset state (mk_parts.py's run, redone here), N frames of the ORIGINAL code:
  f3: irq VBL $1888E, then the main loop's body exec $1810A..$180FA
  f5: irq VBL $17D42, the main loop's body exec $17EDC..$17ED2, then call $15A68 -- the
      fullscreen routine's own writes (texture + letter column) between its border switches
Regions: [BASE, $7FC00) without the part's stack page, and the oracle's own stack ($7FDxx).
M68RUN as mk_parts.py.
"""
import os
import subprocess
import sys
import tempfile
import zlib

from mk_parts import M68RUN, PARTS, RE

FRAME = {
    'f3': ['irq:1888e', 'exec:1810a:180fa'],
    # ($1525E sets d0/d1 = 0/2 and a0/a1 = the shifter's $FF8260/$FF820A before $15A68)
    'f5': ['irq:17d42', 'exec:17edc:17ed2', 'reg:0:0', 'reg:1:2', 'reg:8:ff8260', 'reg:9:ff820a', 'call:15a68'],
}
STACK = {'f3': (0x28000, 0x28400), 'f5': (0x400, 0x600)}
SHOTS = (1, 5, 300)


def main() -> None:
    name = sys.argv[1]
    pc, phase, stop, base, extra = PARTS[name]
    with tempfile.TemporaryDirectory() as tmp:
        cmds = [*extra, 'sr:2700', f'rt:0:{pc:x}:{phase}:{stop:x}']
        done = 0
        for n in SHOTS:
            cmds += FRAME[name] * (n - done) + [f'dump:{tmp}/f{n}.bin']
            done = n
        subprocess.run([M68RUN, os.path.join(RE, 'hatari', f'{name}_entry.bin'), '/dev/null', *cmds],
                       check=True, capture_output=True)
        lo, hi = STACK[name]
        for n in SHOTS:
            d = open(f'{tmp}/f{n}.bin', 'rb').read()
            mem = d[max(base, 0):lo] + d[hi:0x7FC00] if lo >= base else d[base:0x7FC00]
            print(f'    .{{ .vbl = {n}, .mem = 0x{zlib.crc32(mem):08x} }},')


if __name__ == '__main__':
    main()
