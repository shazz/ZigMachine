"""mk_parts.py [PART...]: the assets of F3..F6 (apps/zig/assets/screens/snyd_90/fN.raw).

Each part's set-up runs ONCE on the original code -- m68run's real-time mode from the
part's entry dump (hatari/fN_entry.bin, Hatari RAM at the entry breakpoint) up to its
main loop -- and the memory it leaves, [BASE, $80000), is the asset the Zig port runs on.
M68RUN = the runner (default ./m68run, built from m68run.c; see NOTES.md).
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RE = os.environ.get('RE', HERE)
OUT = os.path.join(HERE, '..', '..', 'apps', 'zig', 'assets', 'screens', 'snyd_90')
M68RUN = os.environ.get('M68RUN', os.path.join(RE, 'm68run'))
# name: (entry PC, Hatari's FrameCycles at it, main loop PC, BASE, extra m68run commands)
# (F5 clears memory down from $80000 in its set-up: it needs the loader's stack, $5F4.)
PARTS = {
    'f3': (0x18000, 76028, 0x180FA, 0x14000, []),
    'f5': (0xC000, 27408, 0x17ED2, 0xC000, ['reg:15:5f4']),
}


def make(name: str) -> None:
    pc, phase, stop, base, extra = PARTS[name]
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, 'ram.bin')
        subprocess.run([M68RUN, os.path.join(RE, 'hatari', f'{name}_entry.bin'), out, *extra, 'sr:2700',
                        f'rt:0:{pc:x}:{phase}:{stop:x}'], check=True, capture_output=True)
        ram = open(out, 'rb').read()
    open(os.path.join(OUT, f'{name}.raw'), 'wb').write(ram[base:0x80000])
    print(name, 0x80000 - base)


if __name__ == '__main__':
    for n in sys.argv[1:] or PARTS:
        make(n)
