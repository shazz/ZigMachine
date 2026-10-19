"""The video probe's block writer (cycles/bvstat.h) against its layout (glass/src/map_cart.zig
"the video probe", via gen/glass_cart.py): the words glass/src/vstat.zig decodes are the words
the firmware writes. The header is compiled for the host with ZM_VSTAT_BLOCK pointed at an array;
frames go in in the firmware's order and the block is dumped after each step."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart as mc  # noqa: E402  (gen/ is on the path only from here)

DRIVER = r"""
#include <stdio.h>
#include <stdint.h>
static uint32_t g_block[VSTAT_WORDS];
#define ZM_VSTAT_BLOCK ((volatile uint32_t*)g_block)
#include "bvstat.h"
static vstat_win w;
static void dump(void) {
    for (unsigned i = 0; i < VSTAT_WORDS; i++) printf("%u%c", (unsigned)g_block[i], i + 1 < VSTAT_WORDS ? ' ' : '\n');
}
static void frame(uint32_t base, uint32_t flags) {
    uint32_t d[VS_NMEAN];
    for (unsigned i = 0; i < VS_NMEAN; i++) d[i] = base + i;
    bvstat_frame(&w, d, flags);
}
int main(void) {
    bvstat_boot(&w, VSF_UNDERRUN_AT_BOOT | 6u << 8); dump();
    for (uint32_t f = 0; f < VSTAT_FRAMES - 1; f++) frame(1000 + 2 * f, 0);
    dump(); /* one frame short of a window: nothing published yet */
    frame(1000 + 2 * (VSTAT_FRAMES - 1), VSF_UNDERRUN); dump();
    frame(VSTAT_MAX_CYCLES / 2, 0); frame(VSTAT_MAX_CYCLES / 2, 0); dump(); /* two slow frames close it */
    for (int f = 0; f < 3; f++) frame(4000000000u, 0); /* 64-bit sums: the mean survives */
    dump();
    return 0;
}
"""


def run_driver(d: Path, *defines: str) -> list[list[int]]:
    cc = shutil.which("cc")
    if not cc:
        pytest.skip("no host C compiler")
    (d / "drv.c").write_text(DRIVER)
    exe = d / "drv"
    subprocess.run([cc, "-std=c11", "-Wall", "-Werror", *defines, "-include", str(FPGA / "gen/glass_cart.h"),
                    "-I", str(FPGA / "cycles"), "-I", str(FPGA / "gen"),
                    "-o", str(exe), str(d / "drv.c")], check=True)  # fmt: skip
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    return [[int(x) for x in line.split()] for line in out.splitlines()]


@pytest.fixture(scope="module")
def steps(tmp_path_factory: pytest.TempPathFactory) -> list[list[int]]:
    return run_driver(tmp_path_factory.mktemp("vstat"))


def means(w: list[int]) -> list[int]:
    return w[mc.VS_FRAME :]


def test_boot_is_an_empty_block_with_its_magic_and_flags(steps: list[list[int]]) -> None:
    w = steps[0]
    assert (w[mc.VS_MAGIC], w[mc.VS_SEQ], w[mc.VS_N]) == (mc.VSTAT_MAGIC, 0, 0)
    assert w[mc.VS_FLAGS] == mc.VSF_UNDERRUN_AT_BOOT | 6 << 8
    assert len(w) == mc.VSTAT_WORDS and not any(means(w))


def test_a_window_publishes_per_frame_means_once_it_is_full(steps: list[list[int]]) -> None:
    check_full_window(steps)


def check_full_window(steps: list[list[int]]) -> None:
    short, full = steps[1], steps[2]
    assert short == steps[0]  # VSTAT_FRAMES - 1 frames: still the boot block
    assert full[mc.VS_N] == mc.VSTAT_FRAMES and full[mc.VS_SEQ] == 2
    mean_base = 1000 + (mc.VSTAT_FRAMES - 1)  # mean of 1000, 1002, ... 1030
    assert means(full) == [mean_base + i for i in range(mc.VSTAT_WORDS - mc.VS_FRAME)]
    assert full[mc.VS_FLAGS] == mc.VSF_UNDERRUN  # the latest frame's sticky bits


def test_slow_frames_close_the_window_early_and_big_sums_do_not_wrap(steps: list[list[int]]) -> None:
    slow, big = steps[3], steps[4]
    assert slow[mc.VS_N] == 2 and means(slow)[0] == mc.VSTAT_MAX_CYCLES // 2
    assert big[mc.VS_N] == 1 and means(big)[0] == 4_000_000_000  # closed on the cap, each frame alone
    assert all(s[mc.VS_SEQ] % 2 == 0 for s in steps) and big[mc.VS_SEQ] > slow[mc.VS_SEQ]


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_break_publishing_the_sums_is_caught(tmp_path: Path) -> None:
    with pytest.raises(AssertionError):
        check_full_window(run_driver(tmp_path, "-DBVSTAT_BREAK_MEAN"))
