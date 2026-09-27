#!/usr/bin/env python3
"""RICK DANGEROUS (Core Design / Firebird 1989): the cart's data, cut from the original.

    python3 tools/rick_dangerous/extract_assets.py

Source: prototypes/rick_re/hatari/ram_entry.bin (gitignored), the 1 MB of RAM at the game's first
instruction $3D6AC, after the Rob Northen Copylock decrypted RICKST.PRG (prototypes/rick_re/
README.md 2). The game runs at fixed absolute addresses, so the cart keeps the same layout: its
memory is the ST's first 512 KB and every table sits where the original reads it.

Writes, into apps/zig/assets/screens/rick_dangerous/:
  image.bin      RAM $0AAA0-$41C58: the font and intro-picture tiles, both tile banks, the block
                 maps and blocks, the title picture, the 212 sprites, the banners, the game's
                 tables and variables at their entry values (submaps, spawn lists, entity types,
                 level records, the hall of fame, the texts, the palettes), the sound driver and
                 the three digis. The reference model reads nothing else of the entry image
                 (checked: verify.py --whole passes with every other byte zeroed).
  snd_driver.bin RAM $34692-$34B98: sound off, play_sound, the VBL tick, the sound table, the
                 digi rates and state, the Timer A install and handler (for sound.s)
  snd_player.bin RAM $34B98-$36618: Ben Daglish's player, the 9 tunes, the sfx records and the
                 digi volume table. Taken from the archive's Rick_Dangerous.sndh bytes $280-$1D00,
                 asserted byte-identical to the game's RAM
  snd_digis.bin  RAM $3DA18-$41C58: the gunshot, explosion and scream samples (0-terminated)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('RICK_RE', '/home/matt/projects/ZigMachine/prototypes/rick_re')
OUT = os.path.join(ROOT, 'apps', 'zig', 'assets', 'screens', 'rick_dangerous')
SNDH = os.path.join(RE, '..', 'sndh_lf', 'Daglish_Ben', 'Rick_Dangerous.sndh')

IMAGE = (0x0AAA0, 0x41C58)
DRIVER = (0x34692, 0x34B98)
PLAYER = (0x34B98, 0x36618)
DIGIS = (0x3DA18, 0x41C58)
ZERO_RUN_LIMIT = 64 * 1024          # apps/zero_segments.mjs fails a cart on a run this long


def longest_zero_run(b):
    best = run = 0
    for v in b:
        run = run + 1 if v == 0 else 0
        best = max(best, run)
    return best


def main():
    ram = open(os.path.join(RE, 'hatari', 'ram_entry.bin'), 'rb').read()
    assert len(ram) >= 0x80000, 'ram_entry.bin is not the 1 MB entry image'
    sndh_path = SNDH if os.path.exists(SNDH) else os.path.join(RE, 'sound', 'Rick_Dangerous.sndh')
    sndh = open(sndh_path, 'rb').read()
    player = sndh[0x280:0x1D00]
    if player != ram[PLAYER[0]:PLAYER[1]]:
        sys.exit('the archive SNDH player is not the game\'s: refusing to mix them')
    os.makedirs(OUT, exist_ok=True)
    image = ram[IMAGE[0]:IMAGE[1]]
    z = longest_zero_run(image)
    assert z < ZERO_RUN_LIMIT, 'image.bin holds a %d-byte zero run' % z
    parts = {'image.bin': image, 'snd_driver.bin': ram[DRIVER[0]:DRIVER[1]],
             'snd_player.bin': player, 'snd_digis.bin': ram[DIGIS[0]:DIGIS[1]]}
    for name, data in parts.items():
        open(os.path.join(OUT, name), 'wb').write(data)
        print('%-15s %6d bytes' % (name, len(data)))
    print('image.bin: longest zero run %d bytes' % z)


if __name__ == '__main__':
    main()
