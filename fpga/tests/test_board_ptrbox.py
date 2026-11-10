"""The pointer's box on the board (glass/src/map_cart.zig VBOX_*, cycles/bptrbox.h): Matt, 9 Nov,
the glass held every cart's pointer to the visible window (f897cb53, for GEM), so pt2-clone and
klystrack, which draw 400x280 planes over the borders, lost their top and bottom rows. ZIGGY's
firmware now writes where the enabled planes draw; glass stops the pointer there (src/mouse.zig
planeBox, its test mouse_box_test.zig). Here: the firmware's word for the real carts' registers,
decoded with glass's rule, and the rectangle a cart publishes (env.hostPointerBox). ZM_RTL_BREAK=1: every plane taken as the visible window
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


def run(exe: Path, *args: object) -> str:
    return subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, check=True).stdout.strip()


def planes(exe: Path, on: int, *regs: tuple[int, int]) -> tuple[int, int] | None:
    return glass_reads(run(exe, "planes", on, *(v for p in (list(regs) + [OFF] * 4)[:4] for v in p)))


def cart(exe: Path, x0: int, y0: int, x1: int, y1: int) -> tuple[int, int, int, int] | None:
    return glass_reads(run(exe, "cart", x0 & 0xFFFF_FFFF, y0 & 0xFFFF_FFFF, x1 & 0xFFFF_FFFF, y1 & 0xFFFF_FFFF))


def span(w: int, tag: int, end: int) -> tuple[int, int] | None:
    if w & glass_cart.VBOX_TAG_MASK != tag:
        return None
    lo, hi = w & glass_cart.VBOX_FIELD_MASK, w >> glass_cart.VBOX_HI_SHIFT & glass_cart.VBOX_FIELD_MASK
    return (lo, hi) if lo < hi <= end else None


def glass_reads(out: str) -> tuple[int, int, int, int] | None:
    """mouse.zig planeBox over the two words: the box in raster pixels (ends exclusive), or None."""
    if out == "none":
        return None
    xw, yw = (int(v, 16) for v in out.split())
    xs, ys = span(xw, glass_cart.VBOX_X_TAG, W), span(yw, glass_cart.VBOX_Y_TAG, H)
    return (xs[0], ys[0], xs[1], ys[1]) if xs and ys else None


def test_gem_is_the_visible_window(ptrbox_test: Path) -> None:
    """GEM's desktop: plane 0 MEDIUM, stride 640 (the arrow stays out of the borders, f897cb53)."""
    assert planes(ptrbox_test, 0b1, (MEDIUM, 640)) == WINDOW


@pytest.mark.parametrize("cart", ["pt2", "klystrack"])
def test_a_fullscreen_plane_alone_is_the_whole_raster(ptrbox_test: Path, cart: str) -> None:
    """kestrel_plane.c: a picture bigger than 320x200 is a FULLSCREEN plane, stride 400; without
    the cart's own rectangle (an SDL port built before hostPointerBox) that is all the firmware knows."""
    assert planes(ptrbox_test, 0b1, (FULLSCREEN, 400)) == WHOLE


@pytest.mark.parametrize(
    ("mode", "stride", "whole"),
    [(NORMAL, 320, 0), (NORMAL, 400, 1), (FULLSCREEN, 400, 1), (SCROLL, 640, 0), (MEDIUM, 640, 0),
     (MEDIUM, 800, 1), (OVERSCAN, 400, 1), (TRUECOLOR, 320, 0), (TC_FULL, 400, 1), (9, 400, 1), (9, 320, 0)],
)  # fmt: skip
def test_each_mode_is_its_rectangle(ptrbox_test: Path, mode: int, stride: int, whole: int) -> None:
    """vwhole.h, the rule vseq_plane_lines also uses (video.zig renderPlane*)."""
    assert int(run(ptrbox_test, "whole", mode, stride)) == whole
    assert planes(ptrbox_test, 0b1, (mode, stride)) == (WHOLE if whole else WINDOW)


def test_the_box_is_the_union_of_the_enabled_planes_only(ptrbox_test: Path) -> None:
    regs = ((MEDIUM, 640), (FULLSCREEN, 400), (NORMAL, 320), (NORMAL, 320))
    assert planes(ptrbox_test, 0b0101, *regs) == WINDOW  # the big plane is off
    assert planes(ptrbox_test, 0b0011, *regs) == WHOLE
    assert planes(ptrbox_test, 0b1000, *regs) == WINDOW


def test_no_plane_enabled_is_the_whole_raster(ptrbox_test: Path) -> None:
    """Nothing drawn to aim at: never a box that traps the pointer."""
    assert planes(ptrbox_test, 0, (MEDIUM, 640)) == WHOLE


# The SDL layer's rectangles (kestrel_sdl2/src/kestrel_ptrbox.c, pointer() coordinates) and where
# glass then stops the pointer: pt2-clone 320x255 at (40, 12) of its 400x280 plane, klystrack 320x240
# at (40, 20): rows 12..266 and 20..259 of the raster, x the visible window.
@pytest.mark.parametrize(
    ("name", "rect", "box"),
    [("pt2", (0, -28, 640, 227), (BX, 12, W - BX, 267)), ("klystrack", (0, -20, 640, 220), (BX, 20, W - BX, 260)),
     ("whole", (-BX, -BY, W - BX, H - BY), WHOLE), ("gem", (0, 0, 640, 200), WINDOW)],
)  # fmt: skip
def test_the_carts_rectangle_is_the_box(
    ptrbox_test: Path, name: str, rect: tuple[int, ...], box: tuple[int, ...]
) -> None:
    assert cart(ptrbox_test, *rect) == box


def test_the_carts_rectangle_is_clipped_to_the_raster(ptrbox_test: Path) -> None:
    assert cart(ptrbox_test, -1000, -1000, 5000, 5000) == WHOLE
    assert cart(ptrbox_test, -(2**31), -(2**31), 2**31 - 1, 2**31 - 1) == WHOLE  # no overflow


@pytest.mark.parametrize("rect", [(0, 0, 0, 200), (10, 0, 5, 200), (900, 0, 1000, 200), (0, -500, 640, -100)])
def test_an_empty_rectangle_leaves_it_to_the_planes(ptrbox_test: Path, rect: tuple[int, ...]) -> None:
    assert run(ptrbox_test, "cart", *(v & 0xFFFF_FFFF for v in rect)) == "none"


def test_the_words_sit_in_free_words_of_the_windows_top() -> None:
    assert glass_cart.KOS_BOOT_FROM_TOP + 4 <= glass_cart.VBOX_Y_FROM_TOP
    assert glass_cart.VBOX_Y_FROM_TOP + 4 <= glass_cart.BOOTSEC_SKIP_FROM_TOP
    assert glass_cart.KOS_FILE_FROM_TOP + 4 <= glass_cart.VBOX_X_FROM_TOP
    assert glass_cart.VBOX_X_FROM_TOP + 4 <= glass_cart.VMODE_FROM_TOP


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_break_every_plane_the_window_is_caught() -> None:
    mutant = build("ptrbox_break", "-DBPTRBOX_BREAK_WINDOW")
    assert planes(mutant, 0b1, (FULLSCREEN, 400)) != WHOLE  # pt2 cut off again
