#!/usr/bin/env python3
"""The MP3 PLAYER's C: for its proofs (apps/mp3_player_check.mjs) and the page (?c=mp3-c.img): a FAT12
image shaped like the board's SD card, with HD/MUSIC/ (C:\\MUSIC) holding the CC0 test files
(apps/zig/assets/mp3/, synthesised by make.sh there). Its own image: docs/gemdos-c.img's and
docs/kos-c.img's contents are pinned by other proofs. Written by tools/kos_fat_fixture.py's Image,
deterministic.

    python3 tools/mp3_c_image.py            # writes docs/mp3-c.img
    python3 tools/mp3_c_image.py --check    # the gate: docs/mp3-c.img is what this writes
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "fpga/tools"))
import sd_layout  # after the path inserts
from kos_fat_fixture import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/mp3-c.img"
MP3 = ROOT / "apps/zig/assets/mp3"
FILES = ("TONES44.MP3", "TONES32.MP3", "TONES48.MP3", "MONO44.MP3")
SECTORS = 1280  # 640 KB


def image() -> bytes:
    hd = sd_layout.HD
    img = Image("SD CARD", SECTORS)
    img.mkdir(hd)
    img.write(f"{hd}/README.TXT", b"C:\\MUSIC holds the MP3 PLAYER's test files (CC0, synthesised).\r\n")
    img.mkdir(f"{hd}/MUSIC")
    for name in FILES:
        img.write(f"{hd}/MUSIC/{name}", (MP3 / name).read_bytes())
    img.write(f"{hd}/MUSIC/NOTES.TXT", b"not an mp3: the player lists *.MP3 only\r\n")
    return img.bytes()


if __name__ == "__main__":
    want = image()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_bytes() != want:
            sys.exit("mp3_c_image: docs/mp3-c.img is not what tools/mp3_c_image.py writes: run it")
        print("mp3_c_image: docs/mp3-c.img ok")
    else:
        OUT.write_bytes(want)
        print(f"mp3_c_image: wrote {OUT.relative_to(ROOT)} ({len(want)} bytes)")
