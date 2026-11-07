#!/usr/bin/env python3
"""c64_1988_rip.py: rip "1988" (Tristar & Red Sector Inc., C64, 2021) for apps/zig/scenes/c64_1988.

Boots the original PRG in VICE (tools/c64/vicemon.py) to the intro's entry ($1E00, after the
exomizer SFX has depacked it) and dumps the 64 KB RAM and the VIC registers there: that is the
program as it runs, and it carries VICE's power-on RAM pattern above the program's end
($E3E6+), which the VIC really shows once a loop (text 3's last byte points the scroller at
sprite block 217, $F640: stripes).

Writes apps/zig/assets/screens/c64_1988/:
  bank3.bin      $C000-$FFFF: the logo's 72 sprite blocks, the font from block 72, the rest
                 of VIC bank 3 ($F000-$F3FF zeroed, as part 1's init clears its screen)
  bank0.bin      $2000-$27FF: part 3's sprite blocks $80-$9F (cubes, balls)
  ripped.bin     what is data, not a formula, in the layout of scenes/c64_1988/data.zig:
                 the three texts, the glyph-width table, the colour fades, part 3's cube
                 bounce (variant A), the VIC registers at $1E00, the text lengths
  tables_ref.bin the original bytes of every table the scene GENERATES (tables.zig), for
                 tables_test.zig: each generator must reproduce the original exactly

  python3 tools/c64_1988_rip.py [prototypes/1988_re/orig/1988.prg]
"""
import hashlib
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "c64"))
from vicemon import Vice  # noqa: E402

OUT = os.path.join(ROOT, "apps/zig/assets/screens/c64_1988")
PRG = os.path.join(ROOT, "prototypes/1988_re/orig/1988.prg")
PRG_MD5 = "03328d45b7dbd0848b1bed325645329c"  # CSDb release 198974's 1988.prg

# (name, address, length): tables the scene regenerates; tables_ref.bin holds them in order
REF = [("logo_x", 0x6001, 100), ("logo_y", 0x6065, 40), ("scroll_x", 0x6397, 101),
       ("scroll_msb", 0x63FC, 101), ("grid_x", 0x51CF, 144), ("grid_msb", 0x525F, 144),
       ("bounce_b", 0x501F, 216), ("wipe_lo", 0xE359, 70), ("wipe_hi", 0xE39F, 70)]


def entry_state(prg: str) -> tuple[bytes, bytes]:
    with tempfile.TemporaryDirectory() as tmp:
        ram, vic = os.path.join(tmp, "ram.bin"), os.path.join(tmp, "vic.bin")
        v = Vice(prg, 0x1E00)
        v.cmd("bank ram")
        v.cmd(f'bsave "{ram}" 0 0000 ffff')
        v.cmd("bank io")
        v.cmd(f'bsave "{vic}" 0 d000 d02e')
        v.close()
        return open(ram, "rb").read(), open(vic, "rb").read()


def text(ram: bytes, k: int) -> bytes:
    """Text k with its index 0 (part 1's copy loop never copies index 0), 146 bytes."""
    src = ram[0x6352 + k] | ram[0x6355 + k] << 8
    return ram[src:src + 146]


def ripped(ram: bytes, vic: bytes) -> bytes:
    """data.zig's layout: offsets 0/146/292 texts, 438 glyph_cut, 694 logo_fade, 712
    bounce_a, 928 grid_fade, 960 vic regs, 1007 text lengths; 1010 bytes."""
    parts = [text(ram, 0), text(ram, 1), text(ram, 2), ram[0x6358:0x6458], ram[0x608F:0x60A1],
             ram[0x4E6F:0x4F47], ram[0x4C9D:0x4CBD], vic[:47], ram[0x634F:0x6352]]
    blob = b"".join(bytes(p) for p in parts)
    assert len(blob) == 1010, len(blob)
    return blob


def main() -> None:
    prg = sys.argv[1] if len(sys.argv) > 1 else PRG
    if hashlib.md5(open(prg, "rb").read()).hexdigest() != PRG_MD5:
        sys.exit(f"{prg}: not the CSDb 1988.prg (md5 {PRG_MD5})")
    ram, vic = entry_state(prg)
    ram = bytearray(ram)
    ram[0xF000:0xF400] = bytes(0x400)
    os.makedirs(OUT, exist_ok=True)
    files = {"bank3.bin": bytes(ram[0xC000:0x10000]), "bank0.bin": bytes(ram[0x2000:0x2800]),
             "ripped.bin": ripped(bytes(ram), vic),
             "tables_ref.bin": b"".join(bytes(ram[a:a + n]) for _, a, n in REF)}
    for name, data in files.items():
        open(os.path.join(OUT, name), "wb").write(data)
        print(f"{name:15} {len(data):6} md5 {hashlib.md5(data).hexdigest()}")


main()
