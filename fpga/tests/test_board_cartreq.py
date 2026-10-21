"""Programs off a data disk on the board (docs/FPGA_GLASS.md, "Programs off a data disk"):
the request block ZIGGY writes is the one ZWINDOW reads (glass/src/map_cart.zig; the glass's
side is glass/src/app_request_test.zig), the shelf prebuilds each program's fat disk under
progs/, and a program's sim image carries the program's descriptor magic."""

from __future__ import annotations

import json
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
WORK = FPGA / "build" / "board_cartreq"
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import ddr_init
import glass_cart
import glass_map
import glass_shelf
import zmd_fat

ST_REPLAY = ROOT / "docs/demo-st_replay.zmd"


@pytest.fixture(scope="module")
def cartreq_test() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "cartreq_test"
    inc = [f"-I{FPGA / d}" for d in ("cycles", "gen")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *inc, str(FPGA / "tests/tb/cartreq_test.c"), "-o", str(exe)],
                   check=True)  # fmt: skip
    return exe


def block(req: int, name: bytes) -> list[int]:
    """map_cart.zig's block: magic, request, bytes, check, the name's words; then what was there."""
    n = min(len(name), glass_cart.CART_REQ_NAME_MAX)
    head = [glass_cart.CART_REQ_MAGIC, req, n, ~(glass_cart.CART_REQ_MAGIC ^ req ^ n) & 0xFFFF_FFFF]
    body = name[:n].ljust(glass_cart.CART_REQ_NAME_MAX, b"\0")
    return head + list(struct.unpack(f"<{len(body) // 4}I", body)) + [0xA5A5_A5A5]


@pytest.mark.parametrize(("req", "name"), [(3, b"BOOT.WSM"), (4, b""), (3, b"X" * 48), (3, b"Y" * 60)])
def test_the_firmwares_block_is_the_one_the_glass_reads(cartreq_test: Path, req: int, name: bytes) -> None:
    out = subprocess.run([str(cartreq_test), str(req), name.hex()], capture_output=True, text=True, check=True)
    assert [int(w, 16) for w in out.stdout.split()] == block(req, name)  # a name too long is cut, never past


def test_the_request_block_sits_between_the_descriptor_and_the_diagnostic() -> None:
    top = glass_map.DDR_CART_BYTES
    start = top - glass_cart.CART_REQ_FROM_TOP
    end = start + 4 * glass_cart.CART_REQ_HEAD_WORDS + glass_cart.CART_REQ_NAME_MAX
    assert top - glass_map.DISK_DESC_FROM_TOP + 4 * glass_map.DISK_DESC_WORDS <= start and end <= top - 0x200
    assert glass_cart.CART_REQUEST not in (glass_map.CART_RESET, glass_map.CART_BOOTING, glass_map.CART_RUNNING,
                                           glass_map.CART_TRAPPED)  # fmt: skip


def _fw(fws: Path, tag: str) -> None:
    (fws / tag).mkdir(parents=True)
    (fws / tag / "fw.bin").write_bytes(tag.encode() * 16)


def test_the_shelf_prebuilds_boot_wsm_as_the_st_replay_carts_image(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    _fw(fws, "gem")
    _fw(fws, "st_replay")
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, tmp_path / "none.h", ("st_replay",)))
    assert rows["zigmachine/progs/demo-st_replay/BOOT.WSM.zmd"].endswith("st_replay/fw.bin (BOOT.WSM)")
    fat = (tmp_path / "sd/progs/demo-st_replay/BOOT.WSM.zmd").read_bytes()
    shelf = ST_REPLAY.read_bytes()
    assert [f[0] for f in zmd_fat.files(fat)] == ["BOOT.WSM", "SAMPLE.RAW", "CART.RV32"]
    assert fat[0x600 : len(shelf)] == shelf[0x600:]  # the same data disk goes back in DDR
    assert not list((tmp_path / "sd").glob("progs/**/SAMPLE.RAW*"))  # a data file is no program


def test_sysinfo_is_a_data_disk_whose_boot_wsm_is_the_sysinfo_carts_image(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    _fw(fws, "gem")
    _fw(fws, "sysinfo")
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, tmp_path / "none.h", ("sysinfo",)))
    assert rows["zigmachine/demo-sysinfo.zmd"].endswith("gem/fw.bin (a data disk: GEM boots)")  # Q has a GEM to go back to
    assert rows["zigmachine/progs/demo-sysinfo/BOOT.WSM.zmd"].endswith("sysinfo/fw.bin (BOOT.WSM)")
    fat = (tmp_path / "sd/progs/demo-sysinfo/BOOT.WSM.zmd").read_bytes()
    assert [f[0] for f in zmd_fat.files(fat)] == ["BOOT.WSM", "JINKS.SND", "GAUNTLET.SAP", "SAMPLE.RAW", "CART.RV32"]
    assert not list((tmp_path / "sd").glob("progs/**/JINKS.SND*"))  # the sound files are data, not programs


def test_a_program_without_its_carts_firmware_is_missing(tmp_path: Path) -> None:
    fws = tmp_path / "board"
    _fw(fws, "gem")
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", fws, tmp_path / "none.h", ("st_replay",)))
    want = f"MISSING: no {fws / 'st_replay' / 'fw.bin'}; make -C fpga board-fw CART=st_replay"
    assert rows["zigmachine/progs/demo-st_replay/BOOT.WSM.zmd"] == want
    assert rows["zigmachine/demo-st_replay.zmd"].endswith("(a data disk: GEM boots)")  # GEM is still staged


def test_a_program_that_is_no_cart_of_the_matrix_is_missing(tmp_path: Path) -> None:
    assert glass_shelf.program_cart(b"\0asm\1\0\0\0 not any cart", tmp_path) is None
    with pytest.raises(subprocess.CalledProcessError):
        glass_shelf.program_cart(b"ZX0!" + bytes(12), tmp_path)  # a broken container: the depacker refuses


def test_a_programs_sim_image_says_so_in_its_descriptor() -> None:
    lines = ddr_init.init_lines(b"\x13" * 64, b"disk", glass_cart.DISK_MAGIC_PROGRAM)
    desc = b"".join(int(word, 16).to_bytes(8, "little") for word in lines[-2:])  # one LE doubleword a line
    assert desc == ddr_init.descriptor(4096, 4, glass_cart.DISK_MAGIC_PROGRAM)
    assert struct.unpack("<I", desc[:4])[0] == glass_cart.DISK_MAGIC_PROGRAM != glass_map.DISK_MAGIC


def test_the_launched_program_quits_back_to_gem_as_scene_hash_says() -> None:
    """ST Replay as GEM launched it (--program: the disk in, no listing): X asks for GEM (request 4)."""
    subprocess.run(["make", "-s", "memmap", "build/host/st_replay/host"], cwd=FPGA, check=True, capture_output=True)
    args = ["20", "5", "--data-disk", str(ST_REPLAY), "--program", "--call", "10:key:120"]
    nat = subprocess.run([str(FPGA / "build/host/st_replay/host"), "st_replay", *args], capture_output=True, text=True,
                         check=True)  # fmt: skip
    js = subprocess.run(["node", "apps/scene_hash.mjs", "docs/demo-st_replay.wasm", *args], cwd=ROOT,
                        capture_output=True, text=True, check=True)  # fmt: skip
    hashes = [[s["hash"] for s in json.loads(r.stdout)["samples"]] for r in (nat, js)]
    assert hashes[0] == hashes[1]
    assert 'cart request 4 "" at frame 10' in nat.stderr and 'cart request 4 ""' in js.stderr
