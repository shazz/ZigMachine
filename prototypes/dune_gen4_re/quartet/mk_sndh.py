"""mk_sndh.py RE_DIR OUT.sndh: build the Dune Gen4 Quartet SNDH from the disk's own files.

RE_DIR holds files/SINGSONG.PRG, files/SOUND2.SET and dune_unpacked.prg (unjek.py). Writes the
incbin inputs of glue.s next to this script, assembles it with vasm, and writes OUT.sndh.
"""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VASM = os.environ.get('VASM', '/home/matt/projects/retrovirology/Bootsector_repairs/tools/vasmm68k_mot')
SONGS = (0x1DF2, 0x24F2, 0x2A1E, 0x3316, 0x3B42)  # DUNE.PRG TEXT offsets, the last = the end
WORK = 16384  # the song work buffer: a song plus room for SingSong to unroll its loops


def fixups(path: str) -> tuple[bytes, list[int]]:
    """TEXT plus every relocated long's offset (relocs.py's walk, the 1 = +254 step kept out)."""
    d = open(path, 'rb').read()
    _, t, dl, _, s = struct.unpack('>HIIII', d[:18])
    p = 28 + t + dl + s
    o = struct.unpack('>I', d[p:p + 4])[0]
    out = [o]
    p += 4
    while d[p]:
        o += 254 if d[p] == 1 else d[p]
        if d[p] != 1:
            out.append(o)
        p += 1
    return d[28:28 + t], out


def main() -> None:
    re_dir, out = sys.argv[1], sys.argv[2]
    text, fix = fixups(os.path.join(re_dir, 'files/SINGSONG.PRG'))
    assert max(fix) < 0x8000
    dune = open(os.path.join(re_dir, 'dune_unpacked.prg'), 'rb').read()[28:]
    w = lambda name, data: open(os.path.join(HERE, name), 'wb').write(data)
    w('singsong.bin', text)
    w('fixups.bin', b''.join(struct.pack('>H', o) for o in fix))
    w('songs.bin', dune[SONGS[0]:SONGS[-1]])
    w('vset.bin', open(os.path.join(re_dir, 'files/SOUND2.SET'), 'rb').read())
    tab = [f'WORK\tequ\t{WORK}', 'songtab:']
    for a, b in zip(SONGS, SONGS[1:]):
        tab.append(f'\tdc.w\t${a - SONGS[0]:04x},${b - a:04x}')
    w('songtab.i', ('\n'.join(tab) + '\n').encode())
    subprocess.run([VASM, '-Fbin', '-m68000', '-no-opt', '-quiet', '-o', os.path.abspath(out),
                    'glue.s'], cwd=HERE, check=True)
    print(out, os.path.getsize(out), 'bytes,', len(fix), 'fixups')


if __name__ == '__main__':
    main()
