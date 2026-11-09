"""The desktop's mode across a program load on the board (glass/src/map_cart.zig DESK_REZ,
rom/rom_deskmode.zig): Matt, 9 Nov, "i ran notepad from deskmode but it seems it switched to
medium res". The word ZIGGY's firmware leaves (cycles/bdeskrez.h, bdiskapp.c) is the one the
glass carries (src/app_request.zig deskRez, its test app_desk_rez_test.zig), and the next image's
firmware hands the ROM exactly the mode, once, and never after a reset (bkos.c)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
WORK = FPGA / "build" / "board_deskrez"
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart

NONE = 0xFF


@pytest.fixture(scope="module")
def deskrez_test() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "deskrez_test"
    inc = [f"-I{FPGA / d}" for d in ("cycles", "gen")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *inc, str(FPGA / "tests/tb/deskrez_test.c"), "-o", str(exe)],
                   check=True)  # fmt: skip
    return exe


def run(exe: Path, *args: str) -> list[str]:
    return subprocess.run([str(exe), *args], capture_output=True, text=True, check=True).stdout.split()


def glass_reads(word: int) -> int | None:
    """app_request.zig deskRez: a tagged mode the ROM knows, else nothing carried."""
    tagged = word & glass_cart.DESK_REZ_TAG_MASK == glass_cart.DESK_REZ_TAG
    return word if tagged and word & ~glass_cart.DESK_REZ_TAG_MASK & 0xFFFF_FFFF <= 2 else None


@pytest.mark.parametrize("mode", [0, 1, 2])
def test_each_mode_goes_through_the_glass_into_the_next_rom(deskrez_test: Path, mode: int) -> None:
    word = int(run(deskrez_test, "word", str(mode))[0], 16)
    assert glass_reads(word) == word
    assert run(deskrez_test, "take", hex(word), "0") == [str(mode), "00000000"]


@pytest.mark.parametrize("mode", [3, NONE, 0x100])
def test_no_desktop_writes_no_word(deskrez_test: Path, mode: int) -> None:
    assert run(deskrez_test, "word", str(mode)) == ["00000000"]


@pytest.mark.parametrize("word", [0, 2, glass_cart.DESK_REZ_TAG | 3, glass_cart.VMODE_TAG | 1])
def test_a_word_the_glass_would_not_carry_gives_the_rom_nothing(deskrez_test: Path, word: int) -> None:
    assert glass_reads(word) is None
    assert run(deskrez_test, "take", hex(word), "0") == [str(NONE), "00000000"]


def test_a_reset_drops_the_word(deskrez_test: Path) -> None:
    """A warm reset keeps the window: the word a program load left must not reach the reset."""
    assert run(deskrez_test, "take", hex(glass_cart.DESK_REZ_TAG | 2), "1") == [str(NONE), "00000000"]


def test_the_word_sits_between_cs_sector_block_and_the_request_block() -> None:
    assert glass_cart.CART_REQ_FROM_TOP < glass_cart.DESK_REZ_FROM_TOP
    assert glass_cart.DESK_REZ_FROM_TOP <= glass_cart.KOS_DRIVE_FROM_TOP - glass_cart.KOS_DRIVE_WORDS * 4
