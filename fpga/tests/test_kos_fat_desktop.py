"""KOS's desktop over a real FAT floppy (docs/KOS_FAT.md F2): an Atari 720 KB image
(tools/kos_fat_fixture.py writes it, no mtools) in drive A, the desktop shell reading it with rom/kos/fat.zig.
The native host equals scene_hash.mjs frame for frame while GEM opens drive A (DEMO.WSM, PIC.PI1,
README.TXT, the GAMES folder) and then GAMES (SAVE.DAT, the LEVELS folder); the empty drive's
desktop differs from the first window on.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
# Drive A clicked and double-clicked, then GAMES (505,65) double-clicked in its window.
SCRIPT = [(5, 40, 30, 0), (10, 40, 30, 1), (11, 40, 30, 0), (20, 40, 30, 2), (21, 40, 30, 0),
          (30, 505, 65, 0), (32, 505, 65, 2), (33, 505, 65, 0)]  # fmt: skip
CALLS = [a for f, x, y, b in SCRIPT for a in ("--call", f"{f}:pointer:{x},{y},{b}")]


@pytest.fixture(scope="module")
def floppy(tmp_path_factory: pytest.TempPathFactory) -> Path:
    out = tmp_path_factory.mktemp("fat") / "kos.st"
    subprocess.run([sys.executable, "tools/kos_fat_fixture.py", str(out)], cwd=ROOT, check=True)
    return out


def hashes(cmd: list[str]) -> list[str]:
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert p.returncode == 0, p.stderr
    return [s["hash"] for s in json.loads(p.stdout)["samples"]]


def both(*args: str) -> list[str]:
    subprocess.run(["make", "-s", "memmap", "build/host/gem/host"], cwd=FPGA, check=True, capture_output=True)
    nat = hashes([str(FPGA / "build/host/gem/host"), "gem", "40", "5", *args])
    js = hashes(["node", "apps/scene_hash.mjs", "docs/demo-gem.wasm", "40", "5", *args])
    assert nat == js
    return nat


def test_the_desktop_opens_a_fat_floppy_and_its_folder_in_both_hosts(floppy: Path) -> None:
    fat = both("--kos", str(floppy), "--post-frames", "0", *CALLS)
    empty = both("--kos", "none", "--post-frames", "0", *CALLS)
    assert fat[0] != empty[0]  # KOS F4: drive A's icon shows only with a disk in
    assert fat[4] != empty[4] and fat[7] != fat[5]  # its listing, then GAMES'


def test_a_fat_floppy_as_a_plain_data_disk_too(floppy: Path) -> None:
    both("--data-disk", str(floppy), *CALLS)  # the pre-KOS path (scene_hash_disk.mjs, host_io.c)


# KOS's C: (docs/KOS_FAT.md F5): the empty drive's desktop with docs/kos-c.img as C:, its icon in
# cell (0,1) double-clicked: the native host's --c-image = scene_hash.mjs's, and C: shows.
OPEN_C = [(5, 40, 70, 0), (10, 40, 70, 1), (11, 40, 70, 0), (20, 40, 70, 2), (21, 40, 70, 0)]
CALLS_C = [a for f, x, y, b in OPEN_C for a in ("--call", f"{f}:pointer:{x},{y},{b}")]


def test_c_drive_shows_and_opens_in_both_hosts() -> None:
    c = both("--kos", "none", "--post-frames", "0", "--c-image", str(ROOT / "docs/kos-c.img"), *CALLS_C)
    bare = both("--kos", "none", "--post-frames", "0", *CALLS_C)
    assert c[0] != bare[0]  # the C: icon
    assert c[7] != c[2]  # its window, opened by the double-click (frame 40 against frame 15)


# The board's first run (4 Nov): a floppy in A: and the card in C: at once. Both hosts agree while
# A:\ opens and then GAMES, and the desktop that repaints only what changed (rom/gem/desktop/
# deskdirty.zig) agrees with itself frame for frame; apps/kos_desk_check.mjs holds what A:\ lists.
def test_a_and_c_together_in_both_hosts(floppy: Path) -> None:
    both("--kos", str(floppy), "--post-frames", "0", "--c-image", str(ROOT / "docs/kos-c.img"), *CALLS)


# C: is the card's /HD, not the card (decisions.md 2026-11-06; apps/zig/scenes/gem_fat.zig): FAT32
# cards as the board's (mkfs.fat + mtools), the boot files, KESTREL/ and CARTS/ beside HD/. C:\ on the
# whole card is pixel for pixel C:\ on a card holding only HD/ (so nothing above HD shows), differs from
# another HD's, and a card with no HD/ has no C: icon at all.
MTOOLS = all(shutil.which(t) for t in ("mkfs.fat", "mmd", "mcopy"))
HD_FILES = {"HD/README.TXT": b"the hard disk\r\n" * 9, "HD/GAMES/SAVE.DAT": b"\x01\x02" * 900}
ABOVE = {"BOOT.BIN": b"\x60" * 9000, "KESTREL/SYSTEM.RV3": b"\x11" * 4000, "KESTREL/KOS/DESKTOP.RV3": b"\x12" * 999,
         "CARTS/SHELF.TXT": b"demo-x.zmd\r\n", "CARTS/DEMOS/DEMO-X.ZMD": b"\x13" * 5000}  # fmt: skip
STAMP = 1_793_000_000  # every file's date, on every card


def fat32_card(img: Path, files: dict[str, bytes]) -> Path:
    """A 64 MB FAT32 image holding `files` (in order: each folder lists them in the dict's order)."""
    env = {**os.environ, "MTOOLS_SKIP_CHECK": "1", "TZ": "UTC"}
    mkfs = ["mkfs.fat", "-F", "32", "-s", "1", "-n", "SD CARD", "-i", "4B4F5331", "-C", str(img), "65536"]
    subprocess.run(mkfs, check=True, capture_output=True)
    made: set[str] = set()
    for n, (rel, data) in enumerate(files.items()):
        parts = rel.split("/")
        for d in ("/".join(parts[:k]) for k in range(1, len(parts))):
            if d not in made:
                subprocess.run(["mmd", "-i", str(img), f"::{d}"], check=True, capture_output=True, env=env)
                made.add(d)
        src = img.with_suffix(f".{n}")
        src.write_bytes(data)
        os.utime(src, (STAMP, STAMP))
        subprocess.run(["mcopy", "-m", "-i", str(img), str(src), f"::{rel}"], check=True, capture_output=True, env=env)
    return img


@pytest.mark.skipif(not MTOOLS, reason="mkfs.fat / mtools not installed")
def test_c_is_the_cards_hd_folder_and_nothing_above_it(tmp_path: Path) -> None:
    def c_frames(name: str, files: dict[str, bytes]) -> list[str]:
        img = fat32_card(tmp_path / f"{name}.img", files)
        return both("--kos", "none", "--post-frames", "0", "--c-image", str(img), *CALLS_C)

    card = c_frames("card", {**ABOVE, **HD_FILES})
    assert card == c_frames("hd_only", HD_FILES)  # its icon, then C:\ = README.TXT and GAMES only
    assert card[7] != c_frames("other_hd", {"HD/OTHER.TXT": b"x"})[7]  # C:\ does list HD's files
    bare = both("--kos", "none", "--post-frames", "0", *CALLS_C)
    assert card[0] != bare[0] and c_frames("no_hd", ABOVE) == bare  # a card with no HD/: no C: icon
