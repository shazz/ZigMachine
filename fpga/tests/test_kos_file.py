"""KOS's C: writes (docs/KOS_GEMDOS.md §7, env.kosFileOp): the request block ZIGGY's firmware writes
(cycles/bkosfreq.h) is the one glass serves (glass/src/map_cart.zig KOS_FILE_*; glass's side, its path gate
and its operations are glass/src/kos_file_test.zig's), the firmware takes only the answer to its own
request, and the block, the C: generation word and the sector block never overlap in the window's top."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
if not (FPGA / "gen" / "glass_cart.py").exists():
    subprocess.run(["make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart as gc  # noqa: E402  (after gen/ exists)
import glass_map  # noqa: E402

M = 0xFFFF_FFFF


@pytest.fixture(scope="module")
def kosfreq(tmp_path_factory: pytest.TempPathFactory) -> Path:
    exe = tmp_path_factory.mktemp("kosfreq") / "kosfreq_test"
    inc = [f"-I{FPGA / d}" for d in ("cycles", "gen")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *inc, str(FPGA / "tests/tb/kosfreq_test.c"), "-o", str(exe)],
                   check=True)  # fmt: skip
    return exe


def run(exe: Path, *args: object) -> str:
    return subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()


@pytest.mark.parametrize("fields", [list(range(1, 12)), [1, 3, 7, 0x21, 0, 32768, 0x10_0000, 0x10_8000, 16, 0, 0], [M] * 11])
def test_the_firmwares_block_is_the_one_glass_reads(kosfreq: Path, fields: list[int]) -> None:
    seq = 0x1234
    words = [int(w, 16) for w in run(kosfreq, seq, *fields).split()]
    check = gc.KOS_FILE_MAGIC ^ seq
    for f in fields:
        check ^= f
    want = [gc.KOS_FILE_MAGIC, seq, *fields, ~check & M, 0, 0, 0xA5A5_A5A5]
    assert words == want
    assert (gc.KF_OP, gc.KF_PATH2_LEN, gc.KF_CHECK, gc.KF_DONE, gc.KF_ACK) == (2, 12, 13, 14, 15)


def test_the_firmware_takes_only_the_answer_to_its_own_request(kosfreq: Path) -> None:
    assert run(kosfreq, "answer", 5, 5, 0) == "00000000"
    assert run(kosfreq, "answer", 5, 5, (-36) & M) == "ffffffdc"  # a TOS code, passed on
    assert run(kosfreq, "answer", 5, 4, 0) == "80000001"  # still the last request's answer: wait


def test_the_firmware_writes_only_to_a_glass_that_serves_the_block(kosfreq: Path) -> None:
    assert run(kosfreq, "ready", gc.KOS_FILE_READY) == "1"
    assert run(kosfreq, "ready", 0) == "0"  # no glass, an older glass, or a load just zeroed the window


def test_the_block_sits_between_the_generation_word_and_the_sector_block() -> None:
    top = glass_map.DDR_CART_BYTES
    start, end = top - gc.KOS_FILE_FROM_TOP, top - gc.KOS_FILE_FROM_TOP + 4 * gc.KOS_FILE_WORDS
    assert top - gc.KOS_MEDIA_FROM_TOP + 4 <= top - gc.KOS_CGEN_FROM_TOP
    assert top - gc.KOS_CGEN_FROM_TOP + 4 <= top - gc.KOS_FILE_READY_FROM_TOP
    assert top - gc.KOS_FILE_READY_FROM_TOP + 4 <= start
    assert end <= top - gc.KOS_DRIVE_FROM_TOP
    assert start % 32 == 0  # KF_DONE and KF_ACK on one D$ line, which the firmware drops each poll
    assert (start + 4 * gc.KF_DONE) // 32 == (start + 4 * gc.KF_ACK) // 32
