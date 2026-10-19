"""Native KESTREL carts (decisions.md 2026-10-17, cycles/native/native.mk): the C and the
hand-written assembly "hello world" build into lean images the board's system accepts, the
header check refuses what glass or bsys.c would, the board-only disk is a bootable disk whose
wasm only explains itself, and glass_sd's shelf stages it like any lean cart. Nothing here
runs a cart: the board is the test (docs/FPGA_TUTORIAL.md, "A native cart")."""

from __future__ import annotations

import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart
import glass_map
import glass_shelf
import native_cart
import split_image
import zmd_fat

V1 = 1 << 16
NATIVE = FPGA / "build/hcycles/split/native_fpu"
needs_rv = pytest.mark.skipif(shutil.which("riscv64-unknown-elf-gcc") is None, reason="the rv32 toolchain builds them")


def build(name: str) -> Path:
    subprocess.run(["make", "-s", "native-cart", f"NAME={name}", "ZM_FPU=1"], cwd=FPGA, check=True, capture_output=True)
    return NATIVE / name


def word(image: bytes, at: int) -> int:
    return struct.unpack_from("<I", image, at)[0]


@needs_rv
@pytest.mark.parametrize("name", ["hello", "hello_asm"])
def test_each_native_cart_builds_to_a_lean_image_this_system_runs(name: str) -> None:
    image = (build(name) / "cart.bin").read_bytes()
    assert native_cart.check(image) == name
    assert split_image.check_pair(V1, image).bss_end > glass_cart.CART_IMG_AT + len(image) - 8
    assert word(image, 20) == native_cart.SHARED_PAGES and word(image, 28) == 16  # pages, a 16-byte instance
    assert word(image, 24) == 0x100100  # cart_high: the 256 bytes of the cart window it owns
    assert len(image) % 8 == 0 and len(image) < 1024


@needs_rv
def test_the_assembly_cart_is_the_c_cart_by_hand() -> None:
    c, asm = ((build(n) / "cart.bin").read_bytes() for n in ("hello", "hello_asm"))
    assert [word(c, i) for i in (0, 4, 8, 20, 24, 28)] == [word(asm, i) for i in (0, 4, 8, 20, 24, 28)]
    assert len(asm) < len(c)


def test_the_header_check_refuses_what_glass_or_the_system_would() -> None:
    base = glass_map.CART_CPU_BASE + glass_cart.CART_IMG_AT
    good = bytearray(128)
    struct.pack_into("<5I", good, 0, glass_cart.CART_HDR_MAGIC, V1, 96, base, base + 160)
    struct.pack_into("<I", good, 20, native_cart.SHARED_PAGES)
    good[80:85] = b"hello"
    assert native_cart.check(bytes(good), V1) == "hello"
    for at, value, why in ((4, 2 << 16, "needs system table 2.0"), (20, 64, "64 pages"), (8, 92, "92 B"),
                           (16, base + 64, "not past"), (80, 0, "empty tag"), (0, 0, "no ZMCA")):  # fmt: skip
        bad = bytearray(good)
        struct.pack_into("<I", bad, at, value)
        with pytest.raises(split_image.SplitError, match=why):
            native_cart.check(bytes(bad), V1)


@needs_rv
def test_the_board_only_disk_boots_a_wasm_that_only_explains_itself() -> None:
    disk = (build("hello") / "disk.zmd").read_bytes()
    assert zmd_fat.bootable(disk) and zmd_fat.files(disk) == []
    assert disk[0x200:0x240].rstrip(b"\0") == b"HELLO WORLD (C)"
    boot, length = word(disk, 0x0E) * 512, word(disk, 0x12)
    assert disk[boot : boot + 4] == b"\0asm" and b"KESTREL ONLY" in disk[boot : boot + length]


@needs_rv
def test_the_shelf_stages_a_native_cart_from_its_own_disk(tmp_path: Path) -> None:
    for name in ("hello", "hello_asm"):
        build(name)
    sysbin = tmp_path / "sys.bin"
    sysbin.write_bytes(b"system" * 8 + struct.pack("<3I", glass_cart.SYS_MAGIC, V1, 7) + bytes(16))
    rows = dict(glass_shelf.build_shelf(tmp_path / "sd", NATIVE, tmp_path / "none.h", (), system=sysbin))
    assert rows["zigmachine/demo-hello.zmd"] == "fpga/build/hcycles/split/native_fpu/hello/disk.zmd + " \
        "build/hcycles/split/native_fpu/hello/cart.bin"  # fmt: skip
    fat = (tmp_path / "sd" / "demo-hello_asm.zmd").read_bytes()
    (name, start, length, kind), = zmd_fat.files(fat)
    assert (name, kind) == ("CART.RV32", glass_map.ZMD_TYPE_RV32)
    (tmp_path / "c.zx0").write_bytes(fat[start : start + length])
    subprocess.run([glass_shelf.zx0unpack(), tmp_path / "c.zx0", tmp_path / "c.bin"], check=True, capture_output=True)
    assert (tmp_path / "c.bin").read_bytes() == (NATIVE / "hello_asm/cart.bin").read_bytes()


@needs_rv
@pytest.mark.parametrize(("edit", "fails"), [("", False), ("NATIVE_IX_guiText 67", True)])
def test_a_table_index_the_assembly_got_wrong_fails_the_build(tmp_path: Path, edit: str, fails: bool) -> None:
    for f in ("native.h", "native_check.c"):
        text = (FPGA / "cycles/native" / f).read_text()
        (tmp_path / f).write_text(text.replace("NATIVE_IX_guiText 68", edit) if edit else text)
    cc = ["riscv64-unknown-elf-gcc", "-march=rv32imf", "-mabi=ilp32f", "-fsyntax-only", f"-I{FPGA / 'cycles'}",
          f"-I{FPGA / 'gen'}", f"-I{FPGA / 'build/vdump'}", str(tmp_path / "native_check.c")]  # fmt: skip
    out = subprocess.run(cc, capture_output=True, text=True)
    assert (out.returncode != 0) == fails and ("table index" in out.stderr) == fails


@pytest.mark.parametrize("src", ["hello.c", "hello_asm.S"])
def test_the_tutorial_shows_each_source_as_it_is(src: str) -> None:
    md = (ROOT / "docs/TUTORIAL.md").read_text()
    blocks = re.findall(r"^```[a-z]*\n(.*?)^```$", md, re.M | re.S)
    assert (FPGA / "cycles/native" / src).read_text() in blocks
