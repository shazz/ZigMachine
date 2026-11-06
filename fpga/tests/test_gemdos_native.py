"""KOS GEMDOS in the native host (docs/KOS_GEMDOS.md §6): GrafX2 (wasm2c'd, as the board runs it) with
docs/gemdos-c.img as C: (--c-image) and its floppy in the drive (--disk) equals scene_hash.mjs frame for frame through the session
apps/gemdos_grafx2_check.mjs drives: F3, Select drive, /C, PICTURES, PLASMA, ZIGPLASM.PI1 loaded. Both
hosts serve C: by the same rules (fpga/host/disk.h host_kos_drive_read, apps/scene_hash_disk.mjs), and
the same GEMDOS (rom/kos/gemdos*.zig, linked in the cart) answers in both. The picture loaded off C:
equals the floppy's own copy loaded (as in the harness), and a host with no C: never gets there.

Phase 2 (docs/KOS_GEMDOS.md §7): GrafX2 SAVES the picture as C:\\PICTURES\\NEW.PI1 (apps/gemdos_grafx2_save.mjs's
session) in both hosts: the same frames, and the two C: images afterwards are byte-identical (the native
host's KFS, wasm2c'd from docs/kos-cfs.wasm, wrote through --c-image-rw; the page's into --c-out), with
NEW.PI1 the floppy's picture byte for byte (mtools, when installed).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
C_IMAGE = str(ROOT / "docs/gemdos-c.img")
DISK = str(ROOT / "docs/demo-grafx2.zmd")
F2, F3, ENTER = 0xE002, 0xE003, 13
PICTURE = ROOT / "apps/ports/grafx2/ownpics/ZIGPLASMA.PI1"


def press(f: int, x: int, y: int, twice: bool = False) -> list[tuple[int, str]]:
    """apps/gemdos_grafx2_check.mjs's click / twice: pointer() takes the window's x, doubled."""
    steps = [(f - 1, 0), (f, 1), (f + 1, 0), (f + 3, 1), (f + 4, 0)] if twice else [(f - 1, 0), (f, 1), (f + 6, 0)]
    return [(sf, f"pointer:{x * 2},{y},{b}") for sf, b in steps]


START = [*press(100, 160, 163), (130, f"key:{F3}"), (132, f"keyUp:{F3}")]
VIA_C = [*START, *press(160, 37, 28), *press(190, 30, 107, True), *press(230, 30, 105, True),
         *press(260, 30, 106, True), *press(290, 30, 114, True)]  # fmt: skip
VIA_FLOPPY = [*START, *press(160, 30, 114, True)]


def key(f: int, k: int) -> list[tuple[int, str]]:
    return [(f, f"key:{k}"), (f + 2, f"keyUp:{k}")]


SAVE = [*VIA_FLOPPY, *key(350, F2), *press(390, 37, 28), *press(420, 30, 107, True), *press(460, 30, 105, True),
        *press(500, 150, 50), *key(510, 78), *key(514, 69), *key(518, 87), *key(530, ENTER)]  # fmt: skip


def calls(script: list[tuple[int, str]]) -> list[str]:
    return [a for f, c in script for a in ("--call", f"{f}:{c}")]


def hashes(cmd: list[str]) -> list[str]:
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-2000:]
    return [s["hash"] for s in json.loads(p.stdout)["samples"]]


def both(*args: str) -> list[str]:
    subprocess.run(["make", "-s", "memmap", "build/host/grafx2/host"], cwd=FPGA, check=True, capture_output=True)
    common = ["340", "30", "--disk", DISK, *args]  # the program GEM launched, its floppy in the drive
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


def test_grafx2_saves_a_picture_to_c_in_both_hosts_alike() -> None:
    subprocess.run(["make", "-s", "memmap", "build/host/grafx2/host"], cwd=FPGA, check=True, capture_output=True)
    with tempfile.TemporaryDirectory() as tmp:
        nat_img, js_img = Path(tmp) / "nat.img", Path(tmp) / "js.img"
        shutil.copy(C_IMAGE, nat_img)
        common = ["600", "30", "--disk", DISK, *calls(SAVE)]
        nat = hashes([str(FPGA / "build/host/grafx2/host"), "grafx2", *common, "--c-image-rw", str(nat_img)])
        js = hashes(["node", "apps/scene_hash.mjs", "docs/demo-grafx2.wasm", *common, "--c-image", C_IMAGE, "--c-out", str(js_img)])
        assert nat == js
        assert nat_img.read_bytes() == js_img.read_bytes()  # the same KFS wrote the same sectors
        assert nat_img.read_bytes() != Path(C_IMAGE).read_bytes()  # ...and it wrote some
        if shutil.which("mtype"):
            got = subprocess.run(["mtype", "-i", str(nat_img), "::HD/PICTURES/NEW.PI1"], capture_output=True, check=True)
            assert got.stdout == PICTURE.read_bytes()
