"""KOS's C: sector by sector (docs/KOS_FAT.md F5, env.kosDriveRead): the request block ZIGGY's
firmware writes (cycles/bkosreq.h) is the one glass serves (glass/src/map_cart.zig KOS_DRIVE_*;
glass's side is glass/src/kos_drive.zig's tests), it sits where nothing else of the window's top
4 KiB does, and the native host's C: (host/disk.h) answers by the same rules as the page's
(docs/sealed-loader.js kosDriveRead) and glass's: the sectors read, 0 for any refusal."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
# A clean tree has no gen/ (the gate's fresh worktree): the memmap the tools import, made first.
if not (FPGA / "gen" / "glass_cart.py").exists():
    subprocess.run(["make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart as gc  # noqa: E402  (after gen/ exists)
import glass_map  # noqa: E402

M = 0xFFFF_FFFF


@pytest.fixture(scope="module")
def kosreq(tmp_path_factory: pytest.TempPathFactory) -> Path:
    exe = tmp_path_factory.mktemp("kosreq") / "kosreq_test"
    inc = [f"-I{FPGA / d}" for d in ("cycles", "gen", "host")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *inc, str(FPGA / "tests/tb/kosreq_test.c"), "-o", str(exe)],
                   check=True)  # fmt: skip
    return exe


def run(exe: Path, *args: object) -> str:
    return subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()


@pytest.mark.parametrize("req", [(1, 2, 0, 1, 0x100), (0xFFFF_FFFF, 2, 123_456, 64, 0x1F0_0000), (7, 1, 5, 0, 3)])
def test_the_firmwares_block_is_the_one_glass_reads(kosreq: Path, req: tuple[int, ...]) -> None:
    seq, unit, sector, count, offset = req
    words = [int(w, 16) for w in run(kosreq, *req).split()]
    check = ~(gc.KOS_DRIVE_MAGIC ^ seq ^ unit ^ sector ^ count ^ offset) & M
    assert words == [gc.KOS_DRIVE_MAGIC, seq, unit, sector, count, offset, check, 0, 0, 0xA5A5_A5A5]


def test_the_firmware_takes_only_the_answer_to_its_own_request(kosreq: Path) -> None:
    assert run(kosreq, "answer", 5, 5, 3) == "3"
    assert run(kosreq, "answer", 5, 4, 3) == "-1"  # still the last request's answer: wait
    assert run(kosreq, "answer", 5, 5, gc.KOS_DRIVE_MAX_SECTORS + 1) == "0"  # nonsense is a refusal


def test_the_block_sits_between_the_media_word_and_the_request_block() -> None:
    start = glass_map.DDR_CART_BYTES - gc.KOS_DRIVE_FROM_TOP
    end = start + 4 * gc.KOS_DRIVE_WORDS
    assert glass_map.DDR_CART_BYTES - gc.KOS_MEDIA_FROM_TOP + 4 <= start
    assert end <= glass_map.DDR_CART_BYTES - gc.CART_REQ_FROM_TOP
    assert start % 32 == 0  # KD_ACK alone on the next D$ line: the firmware drops both, each poll


@pytest.mark.parametrize(
    ("img", "unit", "sector", "count", "dst", "mem", "want"),
    [
        (4096, 2, 0, 8, 0, 8192, 8),  # the whole image
        (4096, 2, 7, 1, 4096, 8192, 1),
        (0, 2, 0, 1, 0, 8192, 0),  # no C: image
        (4096, 0, 0, 1, 0, 8192, 0),  # drive A is not C:
        (4096, 2, 0, 0, 0, 8192, 0),  # nothing asked
        (65536, 2, 0, 65, 0, 65536, 0),  # over one request (64)
        (4096, 2, 7, 2, 0, 8192, 0),  # past the image's end: all or nothing
        (4096, 2, 0, 1, 2, 8192, 0),  # a dst off a word
        (4096, 2, 0, 2, 7680, 8192, 0),  # past the memory's end
    ],
)
def test_the_native_hosts_c_drive_answers_by_the_shared_rules(
    kosreq: Path, img: int, unit: int, sector: int, count: int, dst: int, mem: int, want: int
) -> None:
    assert run(kosreq, "host", img, unit, sector, count, dst, mem) == str(want)
