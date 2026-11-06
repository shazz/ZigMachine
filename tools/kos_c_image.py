#!/usr/bin/env python3
"""KOS's C: for the page and the harnesses (docs/KOS_FAT.md F5): a small FAT12 image standing in for
the board's SD card (?c=kos-c.img on the page, scene_hash.mjs and the native host's --c-image), shaped
like the card (fpga/tools/sd_layout.py: the boot files at the root, KESTREL/, CARTS/ and HD/, which is
what C: shows), every byte synthetic so it never changes with a rebuilt cart. Written by
tools/kos_fat_fixture.py's Image, deterministic.

    python3 tools/kos_c_image.py            # writes docs/kos-c.img
    python3 tools/kos_c_image.py --check    # the gate: docs/kos-c.img is what this writes
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "fpga/tools"))
import sd_layout  # after the path inserts
from kos_fat_fixture import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/kos-c.img"
SECTORS = 400  # 200 KB: the page fetches it whole


def image() -> bytes:
    img = Image("SD CARD", SECTORS)
    img.write("BOOT.BIN", bytes((i * 37 + 11) & 255 for i in range(9000)))
    img.mkdir(sd_layout.SYSTEM)  # never on C: (the shell roots C:\ at HD)
    img.write(f"{sd_layout.SYSTEM}/SYSTEM.RV3", bytes((i * 7 + 3) & 255 for i in range(4000)))
    img.mkdir(sd_layout.CARTS)
    img.write(f"{sd_layout.CARTS}/SHELF.TXT", b"".join(f"demo-{n}.zmd\r\n".encode() for n in ("tutorial", "stniccc")))
    img.mkdir(sd_layout.HD)  # C:\
    img.write(f"{sd_layout.HD}/README.TXT", b"KOS's C: is the SD card's HD folder. On the page this image stands in for it.\r\n")
    for folder, files in (("DEMOS", {"STNICCC.ZMD": 12000}), ("TOOLS", {"SYSINFO.ZMD": 7000, "ST_REPLA.ZMD": 5000}),
                          ("TUTORIAL", {"TUTORIAL.ZMD": 3000})):  # fmt: skip
        img.mkdir(f"{sd_layout.HD}/{folder}")
        for name, size in files.items():
            img.write(f"{sd_layout.HD}/{folder}/{name}", bytes((i * 13 + len(name)) & 255 for i in range(size)))
    return img.bytes()


if __name__ == "__main__":
    want = image()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_bytes() != want:
            sys.exit("kos_c_image: docs/kos-c.img is not what tools/kos_c_image.py writes: run it")
        print("kos_c_image: docs/kos-c.img ok")
    else:
        OUT.write_bytes(want)
        print(f"kos_c_image: wrote {OUT.relative_to(ROOT)} ({len(want)} bytes)")
