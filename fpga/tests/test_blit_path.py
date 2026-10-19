"""hwBlit's own cost on the board: cycles/bblit.c as the board image builds it, on the board's cart
core (VexRiscv_I16w2D4SealFpu) in Verilator, every store held as long as a blocking DDR write
(tests/blitpath/blitpath.c, tests/tb/dcache_tb.cpp's store wait).

The ZIGGY bench measured an 8x8 FILL at ~1,220 cycles through hwBlit against ~540 poking CHISEL
straight; ~12 of the difference's stores were bblit.c's statistics, which nothing on the board
reads. These tests hold the board path to the contract (CYCLES and STATUS where the machine
leaves them, the machine's own code below OFF_VRAM and before VBASE) and to its budget: a few
bus writes a call beyond GO, not a dozen. The break test puts the statistics back.

Needs Verilator, riscv64-unknown-elf-gcc and build/vexgen/VexRiscv_I16w2D4SealFpu.v (skips
without them, as test_blit_dcache.py)."""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
sys.path.insert(0, str(FPGA / "tools"))
import video_dump  # after the path insert: writes build/vdump/zm_memmap.h
from test_blit_dcache import core_tb  # noqa: F401 -- the fixture: the core in Verilator

BUILD = FPGA / "build" / "tests" / "blitpath"
STORE_WAIT = 16  # extra cycles a store is held: ~18 a store, the bench's st.sw
GO_POLL_WRITES = 1  # the floor: GO


def _elf(src: Path, out: Path, defs: tuple[str, ...] = ("-DZM_BOARD",)) -> Path:
    here = FPGA / "tests/blitpath"
    cmd = ["riscv64-unknown-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "--specs=picolibc.specs"]
    cmd += ["-nostdlib", "-nostartfiles", "-ffunction-sections", "-Wl,--gc-sections", *defs, "-DZM_BLIT_HW"]
    cmd += [f"-I{here}", f"-I{FPGA / 'cycles'}"]
    cmd += [f"-I{video_dump.memmap_header().parent}", "-T", str(FPGA / "tests/dcache/link.ld")]
    cmd += [str(FPGA / "tests/dcache/start.S"), str(here / "blitpath.c"), str(src), "-lgcc", "-o", str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, check=True, capture_output=True)
    return out


def _run(tb: Path, elf: Path) -> tuple[int, dict[int, int], str]:
    r = subprocess.run([str(tb), str(elf), str(STORE_WAIT)], capture_output=True, text=True, timeout=300, check=False)
    rep = {int(v) // 1000000: int(v) % 1000000 for v in re.findall(r"^REPORT (\d+)$", r.stdout, re.MULTILINE)}
    return r.returncode, rep, r.stdout


def test_the_board_path_keeps_the_contract_and_costs_a_few_stores(core_tb: Path) -> None:  # noqa: F811
    code, rep, out = _run(core_tb, _elf(FPGA / "cycles/bblit.c", BUILD / "board.elf"))
    assert code == 0, f"check {code} failed\n{out}"
    print(f"8x8 FILL: hwBlit {rep[1]} cycles, {rep[2]} writes a call; GO + poll {rep[3]} cycles, {rep[4]} writes")
    assert rep[4] == GO_POLL_WRITES
    assert rep[2] <= GO_POLL_WRITES + 2, f"hwBlit stores {rep[2]} words a call: the statistics are back?\n{out}"


def test_the_sim_image_still_counts_every_call(core_tb: Path) -> None:  # noqa: F811
    """Without ZM_BOARD (the sim's image) the statistics stay: "ZM BF" and "ZM BLIT" read them."""
    code, rep, out = _run(core_tb, _elf(FPGA / "cycles/bblit.c", BUILD / "sim.elf", ()))
    assert code == 0, f"check {code} failed\n{out}"
    assert rep[2] >= GO_POLL_WRITES + 10, f"the sim image lost its statistics ({rep[2]} writes a call)\n{out}"


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_statistics_left_in_the_board_image_are_caught(core_tb: Path) -> None:  # noqa: F811
    work = BUILD / "mutants" / "stats_on_board"
    work.mkdir(parents=True, exist_ok=True)
    text = (FPGA / "cycles/bblit.c").read_text()
    old = "#ifndef ZM_BOARD\n#define BBLIT_STATS 1\n#endif"
    assert text.count(old) == 1, "bblit.c's statistics switch is not where the break test expects it"
    (work / "bblit.c").write_text(text.replace(old, "#define BBLIT_STATS 1"))
    shutil.copy(FPGA / "cycles/bblit.h", work / "bblit.h")
    code, rep, out = _run(core_tb, _elf(work / "bblit.c", work / "board.elf"))
    assert code != 0 or rep[2] > GO_POLL_WRITES + 2, f"the statistics went unnoticed\n{out}"
