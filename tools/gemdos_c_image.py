#!/usr/bin/env python3
"""KOS GEMDOS's C: for the proofs (docs/KOS_GEMDOS.md §6): a FAT12 image shaped like the board's SD card
(the boot files, KESTREL/, CARTS/ and HD/, which is C:\\), with pictures two and three levels down for
GrafX2 to load: HD/PICTURES/ZIGWAVES.PI1 and HD/PICTURES/PLASMA/ZIGPLASM.PI1 + .NEO, our own art
(apps/ports/grafx2/ownpics, the same files the GrafX2 floppy carries, so a picture loaded off C: can be
held against the same picture loaded off the floppy). Its own image, not docs/kos-c.img: that one's
listing is pinned by the desktop's proofs. Written by tools/kos_fat_fixture.py's Image, deterministic.

    python3 tools/gemdos_c_image.py            # writes docs/gemdos-c.img
    python3 tools/gemdos_c_image.py --check    # the gate: docs/gemdos-c.img is what this writes
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "fpga/tools"))
import sd_layout  # after the path inserts
from kos_fat_fixture import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/gemdos-c.img"
PICS = ROOT / "apps/ports/grafx2/ownpics"
SECTORS = 640  # 320 KB


def image() -> bytes:
    hd = sd_layout.HD
    img = Image("SD CARD", SECTORS)
    img.write("BOOT.BIN", bytes((i * 37 + 11) & 255 for i in range(9000)))
    img.mkdir(sd_layout.SYSTEM)  # never on C: (C:\ is HD)
    img.write(f"{sd_layout.SYSTEM}/SYSTEM.RV3", bytes((i * 7 + 3) & 255 for i in range(4000)))
    img.mkdir(sd_layout.CARTS)
    img.write(f"{sd_layout.CARTS}/SHELF.TXT", b"demo-grafx2.zmd\r\n")
    img.mkdir(hd)
    img.write(f"{hd}/README.TXT", b"C:\\ is the SD card's HD folder. GEMDOS reads it.\r\n" * 3)
    img.mkdir(f"{hd}/PICTURES")
    img.write(f"{hd}/PICTURES/ZIGWAVES.PI1", (PICS / "ZIGWAVES.PI1").read_bytes())
    img.mkdir(f"{hd}/PICTURES/PLASMA")
    img.write(f"{hd}/PICTURES/PLASMA/ZIGPLASM.PI1", (PICS / "ZIGPLASMA.PI1").read_bytes())
    img.write(f"{hd}/PICTURES/PLASMA/ZIGPLASM.NEO", (PICS / "ZIGPLASMA.NEO").read_bytes())
    img.mkdir(f"{hd}/TEXTS")
    for k in range(20):  # a folder that needs more than one directory sector
        img.write(f"{hd}/TEXTS/NOTE{k:02d}.TXT", f"note {k}\r\n".encode() * (k + 1))
    img.write(f"{hd}/EMPTY.DAT", b"")
    return img.bytes()


if __name__ == "__main__":
    want = image()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_bytes() != want:
            sys.exit("gemdos_c_image: docs/gemdos-c.img is not what tools/gemdos_c_image.py writes: run it")
        print("gemdos_c_image: docs/gemdos-c.img ok")
    else:
        OUT.write_bytes(want)
        print(f"gemdos_c_image: wrote {OUT.relative_to(ROOT)} ({len(want)} bytes)")
