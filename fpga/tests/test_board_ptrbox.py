"""The pointer's box on the board (glass/src/map_cart.zig VBOX_*, cycles/bptrbox.h): Matt, 9 Nov,
the glass held every cart's pointer to the visible window (f897cb53, for GEM), so pt2-clone and
klystrack, which draw 400x280 planes over the borders, lost their top and bottom rows. ZIGGY's
firmware now writes where the enabled planes draw; glass stops the pointer there (src/mouse.zig
planeBox, its test mouse_box_test.zig). Here: the firmware's word for the real carts' registers,
decoded with glass's rule. ZM_RTL_BREAK=1: every plane taken as the visible window
(BPTRBOX_BREAK_WINDOW, the clamp that cut pt2 off) must be caught."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
WORK = FPGA / "build" / "board_ptrbox"
subprocess.run(["make", "-s", "gen/glass_cart.h", "gen/glass_map.py"], cwd=FPGA, check=True)  # VBOX_*, fresh
sys.path.insert(0, str(FPGA / "gen"))
sys.path.insert(0, str(FPGA / "tools"))
import glass_cart
import glass_map
import video_dump  # writes build/vdump/zm_memmap.h

NORMAL, FULLSCREEN, SCROLL, MEDIUM, OVERSCAN, TRUECOLOR, TC_FULL = range(7)
W, H, BX, BY = glass_map.PTR_WIDTH, glass_map.PTR_HEIGHT, glass_map.PTR_BORDER_X, glass_map.PTR_BORDER_Y
WHOLE = (0, 0, W, H)
WINDOW = (BX, BY, W - BX, H - BY)
OFF = (NORMAL, 320)


def build(name: str, *defs: str) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    video_dump.memmap_header()
    exe = WORK / name
    inc = [f"-I{FPGA / d}" for d in ("cycles", "gen", "build/vdump")]
    subprocess.run(["clang", "-std=c11", "-Wall", "-Werror", *defs, *inc, str(FPGA / "tests/tb/ptrbox_test.c"), "-o", str(exe)],
                   check=True)  # fmt: skip
    return exe


@pytest.fixture(scope="module")
def ptrbox_test() -> Path:
    return build("ptrbox_test")


def word(exe: Path, on: int, *planes: tuple[int, int]) -> int:
    regs = [str(v) for p in (list(planes) + [OFF] * 4)[:4] for v in p]
    return int(subprocess.run([str(exe), str(on), *regs], capture_output=True, text=True, check=True).stdout, 16)


def glass_reads(w: int) -> tuple[int, int, int, int] | None:
    """mouse.zig planeBox: the box in raster pixels (ends exclusive), or None (the whole raster)."""
    if w & glass_cart.VBOX_TAG_MASK != glass_cart.VBOX_TAG:
        return None
    f = glass_cart.VBOX_FIELD_MASK
    x0 = (w >> glass_cart.VBOX_X0_SHIFT & f) * glass_cart.VBOX_X_UNIT
    x1 = (w >> glass_cart.VBOX_X1_SHIFT & f) * glass_cart.VBOX_X_UNIT
    y0 = (w >> glass_cart.VBOX_Y0_SHIFT & f) * glass_cart.VBOX_Y_UNIT
    y1 = (w >> glass_cart.VBOX_Y1_SHIFT & f) * glass_cart.VBOX_Y_UNIT
    return (x0, y0, x1, y1) if x0 < x1 <= W and y0 < y1 <= H else None


def test_gem_is_the_visible_window(ptrbox_test: Path) -> None:
    """GEM's desktop: plane 0 MEDIUM, stride 640 (the arrow stays out of the borders, f897cb53)."""
    assert glass_reads(word(ptrbox_test, 0b1, (MEDIUM, 640))) == WINDOW


@pytest.mark.parametrize("cart", ["pt2", "klystrack"])
def test_an_sdl_port_over_the_borders_is_the_whole_raster(ptrbox_test: Path, cart: str) -> None:
    """kestrel_plane.c: a picture bigger than 320x200 is a FULLSCREEN plane, stride 400."""
    assert glass_reads(word(ptrbox_test, 0b1, (FULLSCREEN, 400))) == WHOLE


@pytest.mark.parametrize(
    ("mode", "stride", "whole"),
    [(NORMAL, 320, 0), (NORMAL, 400, 1), (FULLSCREEN, 400, 1), (SCROLL, 640, 0), (MEDIUM, 640, 0),
     (MEDIUM, 800, 1), (OVERSCAN, 400, 1), (TRUECOLOR, 320, 0), (TC_FULL, 400, 1), (9, 400, 1), (9, 320, 0)],
)  # fmt: skip
def test_each_mode_is_its_rectangle(ptrbox_test: Path, mode: int, stride: int, whole: int) -> None:
    """vwhole.h, the rule vseq_plane_lines also uses (video.zig renderPlane*)."""
    out = subprocess.run(
        [str(ptrbox_test), "whole", str(mode), str(stride)], capture_output=True, text=True, check=True
    )
    assert int(out.stdout) == whole
    assert glass_reads(word(ptrbox_test, 0b1, (mode, stride))) == (WHOLE if whole else WINDOW)


def test_the_box_is_the_union_of_the_enabled_planes_only(ptrbox_test: Path) -> None:
    planes = ((MEDIUM, 640), (FULLSCREEN, 400), (NORMAL, 320), (NORMAL, 320))
    assert glass_reads(word(ptrbox_test, 0b0101, *planes)) == WINDOW  # the big plane is off
    assert glass_reads(word(ptrbox_test, 0b0011, *planes)) == WHOLE
    assert glass_reads(word(ptrbox_test, 0b1000, *planes)) == WINDOW


def test_no_plane_enabled_is_the_whole_raster(ptrbox_test: Path) -> None:
    """Nothing drawn to aim at: never a box that traps the pointer."""
    assert glass_reads(word(ptrbox_test, 0, (MEDIUM, 640))) == WHOLE


def test_the_word_sits_between_kos_boot_words_and_the_boot_sectors_skip_word() -> None:
    assert glass_cart.KOS_BOOT_FROM_TOP + 4 <= glass_cart.VBOX_FROM_TOP
    assert glass_cart.VBOX_FROM_TOP + 4 <= glass_cart.BOOTSEC_SKIP_FROM_TOP


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_break_every_plane_the_window_is_caught() -> None:
    mutant = build("ptrbox_break", "-DBPTRBOX_BREAK_WINDOW")
    assert glass_reads(word(mutant, 0b1, (FULLSCREEN, 400))) != WHOLE  # pt2 cut off again
