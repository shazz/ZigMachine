"""KOS GEMDOS in the native host (docs/KOS_GEMDOS.md §6): GrafX2 (wasm2c'd, as the board runs it) with
docs/gemdos-c.img as C: (--c-image) equals scene_hash.mjs frame for frame through the session
apps/gemdos_grafx2_check.mjs drives: F3, Select drive, /C, PICTURES, PLASMA, ZIGPLASM.PI1 loaded. Both
hosts serve C: by the same rules (fpga/host/disk.h host_kos_drive_read, apps/scene_hash_disk.mjs), and
the same GEMDOS (rom/kos/gemdos*.zig, linked in the cart) answers in both. The picture loaded off C:
equals the floppy's own copy loaded (as in the harness), and a host with no C: never gets there.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
C_IMAGE = str(ROOT / "docs/gemdos-c.img")
DISK = str(ROOT / "docs/demo-grafx2.zmd")
F3 = 0xE003


def press(f: int, x: int, y: int, twice: bool = False) -> list[tuple[int, str]]:
    """apps/gemdos_grafx2_check.mjs's click / twice: pointer() takes the window's x, doubled."""
    steps = [(f - 1, 0), (f, 1), (f + 1, 0), (f + 3, 1), (f + 4, 0)] if twice else [(f - 1, 0), (f, 1), (f + 6, 0)]
    return [(sf, f"pointer:{x * 2},{y},{b}") for sf, b in steps]


START = [*press(100, 160, 163), (130, f"key:{F3}"), (132, f"keyUp:{F3}")]
VIA_C = [*START, *press(160, 37, 28), *press(190, 30, 107, True), *press(230, 30, 105, True),
         *press(260, 30, 106, True), *press(290, 30, 114, True)]  # fmt: skip
VIA_FLOPPY = [*START, *press(160, 30, 114, True)]


def calls(script: list[tuple[int, str]]) -> list[str]:
    return [a for f, c in script for a in ("--call", f"{f}:{c}")]


def hashes(cmd: list[str]) -> list[str]:
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-2000:]
    return [s["hash"] for s in json.loads(p.stdout)["samples"]]


def both(*args: str) -> list[str]:
    subprocess.run(["make", "-s", "memmap", "build/host/grafx2/host"], cwd=FPGA, check=True, capture_output=True)
    common = ["340", "30", "--data-disk", DISK, "--program", *args]
    nat = hashes([str(FPGA / "build/host/grafx2/host"), "grafx2", *common])
    js = hashes(["node", "apps/scene_hash.mjs", "docs/demo-grafx2.wasm", *common])
    assert nat == js
    return nat


def test_grafx2_loads_a_picture_from_c_in_both_hosts_as_from_the_floppy() -> None:
    via_c = both("--c-image", C_IMAGE, *calls(VIA_C))
    via_floppy = both("--c-image", C_IMAGE, *calls(VIA_FLOPPY))
    assert via_c[-1] == via_floppy[-1]  # frame 340: ZIGPLASM.PI1, off C:\PICTURES\PLASMA and off the floppy
    assert via_c[-1] != via_c[-3]  # ...and it is not the selector of frame 280
    no_c = both(*calls(VIA_C))  # no C: image: no "/C" in the drive list, the picture never loads
    assert no_c[-1] != via_c[-1]
