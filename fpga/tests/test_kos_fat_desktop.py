"""KOS's desktop over a real FAT floppy (docs/KOS_FAT.md F2): an Atari 720 KB image
(tools/kos_fat_fixture.py writes it, no mtools) in drive A, the desktop shell reading it with rom/kos/fat.zig.
The native host equals scene_hash.mjs frame for frame while GEM opens drive A (DEMO.WSM, PIC.PI1,
README.TXT, the GAMES folder) and then GAMES (SAVE.DAT, the LEVELS folder); the empty drive's
desktop differs from the first window on.
"""

from __future__ import annotations

import json
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
