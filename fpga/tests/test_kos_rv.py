"""KOS F3b (docs/KOS_FAT.md): a floppy program's own board image, NAME.RV beside NAME.WSM, written by
fpga/tools/kos_rv.py in glass/src/app_floppy_rv.zig's container ("ZMRV", version 1, the wasm's
SHA-256, the ZX0-packed lean cart). A cart the system would refuse (another table major) is never
written; `floppy` puts each cart's .WSM and .RV on an Atari FAT12 image KOS's reader lists."""

from __future__ import annotations

import hashlib
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
# A clean tree has no gen/ (the gate's fresh worktree): the memmap split_image imports, made first.
if not (FPGA / "gen" / "glass_cart.py").exists():
    subprocess.run(["make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart  # noqa: E402  (after gen/ exists)
import glass_map
import kos_rv
from glass_shelf import Images
from glass_zx0 import zx0unpack

V1 = 1 << 16
ZIG = shutil.which("zig") or str(Path.home() / ".local/zig/0.16.0/zig")


def lean_cart(version: int, size: int = 256) -> bytes:  # test_cart_split.py's
    body = bytearray((i * 29 + 3) & 255 for i in range(size))
    struct.pack_into("<II", body, 0, glass_cart.CART_HDR_MAGIC, version)
    base = glass_map.CART_CPU_BASE + glass_cart.CART_IMG_AT
    struct.pack_into("<I", body, glass_cart.CART_HDR_BSS_END_AT, base + size + 64)
    return bytes(body)


def fw_dir(tmp: Path, version: int) -> Path:
    for cart in ("tutorial", "sysinfo"):
        (tmp / "fw" / cart).mkdir(parents=True)
        (tmp / "fw" / cart / "cart.bin").write_bytes(lean_cart(version))
    return tmp / "fw"


def test_an_rv_is_the_wasms_hash_and_its_packed_board_image(tmp_path: Path) -> None:
    rv = kos_rv.rv_of("tutorial", Images(fw_dir(tmp_path, V1), V1))
    wasm = (ROOT / "docs/demo-tutorial.wasm").read_bytes()
    assert (rv[:4], rv[4:8], rv[8:40]) == (b"ZMRV", b"\x01\0\0\0", hashlib.sha256(wasm).digest())
    (tmp_path / "img.zx0").write_bytes(rv[40:])
    subprocess.run([zx0unpack(), tmp_path / "img.zx0", tmp_path / "img"], check=True, capture_output=True)
    assert (tmp_path / "img").read_bytes() == lean_cart(V1)


def test_a_cart_the_system_refuses_gets_no_rv(tmp_path: Path) -> None:
    with pytest.raises(SystemExit, match="REFUSED"):
        kos_rv.rv_of("tutorial", Images(fw_dir(tmp_path, 2 << 16), V1))  # a cart for table 2.x, a 1.x system
    with pytest.raises(SystemExit, match="MISSING"):
        kos_rv.rv_of("stniccc", Images(tmp_path / "fw", V1))


def test_a_program_floppy_holds_each_carts_wsm_and_rv(tmp_path: Path) -> None:
    out = tmp_path / "progs.st"
    kos_rv.floppy(out, ["tutorial", "sysinfo"], Images(fw_dir(tmp_path, V1), V1))
    dump = tmp_path / "fat_dump"
    subprocess.run([ZIG, "build-exe", "-ODebug", str(ROOT / "rom/kos/fat_dump.zig"), f"-femit-bin={dump}"],
                   check=True, cwd=tmp_path, capture_output=True)  # fmt: skip
    lines = subprocess.run([dump, out], check=True, capture_output=True, text=True).stdout.splitlines()
    names = [ln.split("\t")[0] for ln in lines[1:]]
    assert (lines[0], names) == ("fat12", ["TUTORIAL.WSM", "TUTORIAL.RV", "SYSINFO.WSM", "SYSINFO.RV"])


def test_carts_whose_83_names_collide_are_refused(tmp_path: Path) -> None:
    with pytest.raises(SystemExit, match="8.3"):
        kos_rv.floppy(tmp_path / "x.st", ["replicants_emlyn", "replicants_other"], Images(tmp_path, V1))
