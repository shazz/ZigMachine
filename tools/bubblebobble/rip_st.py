#!/usr/bin/env python3
"""BUBBLE BOBBLE (Firebird 1987): the cart's data, cut from the ST game.

    python3 tools/bubblebobble/rip_st.py

Source: $BUBBLE_RE (default prototypes/bubble_re in the main checkout, gitignored): files/BUBBLE.PRG
and files/GRAPHICS/, the game as the Deep Thought #1 compilation disk holds it (disks/DEEP1.ST,
plain FAT; the original Firebird disk is the Pasti image disks/Bubble Bobble.stx).

Writes, into apps/zig/assets/screens/bubblebobble/:
  text.bin     BUBBLE.PRG's TEXT segment relocated to $10000 (st_prg.BASE) with every translated
               instruction's bytes zeroed: the variables, tables, texts and the font the game keeps
               between its routines, and none of its code (that is gen/, from st_recomp.py)
  <name>       the eleven GRAPHICS\\ files the game Fopens, as far as the game reads them (tos.zig serves them):
               the round maps, the enemy and air-current tables, the sprite banks, the four
               pictures and the music data
  snd_driver.bin  TEXT $A7AE-$AFC9 relocated: the game's sound driver, for sound.s (the SNDH)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import st_prg  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('BUBBLE_RE', '/home/matt/projects/ZigMachine/prototypes/bubble_re')
OUT = os.path.join(ROOT, 'apps', 'zig', 'assets', 'screens', 'bubblebobble')
FILES = ['BBLOCKS.PI1', 'BUBBLE.SPR', 'SPIC.PI1', 'AIRFLOW.DAT', 'UNSHIFT.SPR', 'BDATA.DAT',
         'FRUIT.SPR', 'SECRET.PI1', 'EXTEND.PI1', 'DWARF.SPR', 'MUSIC.DAT']
# The game's Fread asks for less than these files hold ($3608, $3634): the rest is never read.
DRIVER = (0xA7AE, 0xAFCA)  # the sound driver's code and data, TEXT offsets
READ_LEN = {'BBLOCKS.PI1': 14080, 'AIRFLOW.DAT': 1545}


def main():
    prg, insns, _ = st_prg.load(RE)
    data = bytearray(prg.image)
    for a, i in insns.items():
        data[a - st_prg.BASE:a - st_prg.BASE + i.size] = bytes(i.size)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'text.bin'), 'wb') as f:
        f.write(data)
    drv = prg.image[DRIVER[0]:DRIVER[1]]
    with open(os.path.join(OUT, 'snd_driver.bin'), 'wb') as f:
        f.write(drv)
    for name in FILES:
        src = open(os.path.join(RE, 'files', 'GRAPHICS', name), 'rb').read()
        with open(os.path.join(OUT, name.lower()), 'wb') as f:
            f.write(src[:READ_LEN.get(name, len(src))])
    print('text.bin %d bytes (%d of code zeroed), %d files' % (
        len(data), sum(i.size for i in insns.values()), len(FILES)))


if __name__ == '__main__':
    main()
