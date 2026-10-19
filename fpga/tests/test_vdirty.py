"""The board's dirty-line planner (cycles/vdirty.h), proven natively (host/vdirty_main.c): every
frame the picture the board would keep, where only the lines the planner did not skip are
composited again, is compared whole with a full composite of the same frame. Zero rows may
differ. The carts cover what the planner must see: plane rows (scroll), palettes (joust), the
background and BEAM lines (union_intro, dhs_0pxl0reg), a copper on the top plane (tutorial),
several planes (empire), the GEM pointer drawn over each picture (gem, ZM_VD_CURSOR=1).

The board only plans while planning pays (cycles/vadapt.h): with ZM_VD_ADAPT=1 the proof runs
that bypass on a cost model, and it must engage where nothing can be skipped (medium_overscan,
whose rows are all compared and all new), stay out of the way where most lines are skipped
(gem), and never cost a mismatch across the switches.

Break tests (ZM_RTL_BREAK=1): each VD_BREAK mutant forgets one input, and the proof must then
find a skipped row that a full composite paints differently."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
FRAMES = "300"
CARTS = ["scroll", "joust", "union_intro", "dhs_0pxl0reg", "tutorial", "empire", "gem"]
LINE = re.compile(
    r"VDIRTY \S+ frames \d+ lines (\d+) skipped (\d+) unknown \d+ moved (\d+) bypassed (\d+) mismatched (\d+)"
)


def proof(cart: str, mutant: str = "", adapt: bool = False) -> tuple[int, int, int, int, int]:
    """(lines, skipped, moved, mismatched, bypassed frames) over FRAMES frames."""
    subprocess.run(["make", "-s", "memmap", "host-vdirty", f"CART={cart}", f"VD_BREAK={mutant}"], cwd=FPGA,
                   check=True, capture_output=True)  # fmt: skip
    binary = FPGA / f"build/host/{cart}/host_vdirty{'_' + mutant if mutant else ''}"
    env = dict(os.environ, ZM_VD_CURSOR="1" if cart == "gem" else "0", ZM_VD_ADAPT="1" if adapt else "0")
    out = subprocess.run([str(binary), cart, FRAMES], env=env, capture_output=True, text=True, check=False)
    m = LINE.search(out.stdout)
    assert m, out.stdout + out.stderr
    return int(m[1]), int(m[2]), int(m[3]), int(m[5]), int(m[4])


@pytest.mark.parametrize("cart", CARTS)
def test_a_skipped_row_is_what_a_full_composite_paints(cart: str) -> None:
    lines, skipped, moved, bad, _ = proof(cart)
    assert bad == 0 and moved == 0
    assert skipped > 0  # every one of these carts has lines to skip: the proof is not vacuous


BREAKS = [("ROWS", "scroll"), ("PAL", "joust"), ("BG", "union_intro"), ("BG", "dhs_0pxl0reg"),
          ("HANDLER", "tutorial"), ("PICTURE", "scroll"), ("OVERDRAWN", "gem")]  # fmt: skip


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("mutant", "cart"), BREAKS)
def test_a_forgotten_input_is_caught(mutant: str, cart: str) -> None:
    assert proof(cart, mutant)[3] > 0


def test_the_plan_is_bypassed_where_it_cannot_pay() -> None:
    lines, skipped, moved, bad, bypassed = proof("medium_overscan", adapt=True)
    assert bad == 0
    assert bypassed >= int(FRAMES) * 9 // 10  # one probe every VA_OFF_FRAMES, the rest bypassed


def test_the_plan_stays_on_where_it_pays() -> None:
    lines, skipped, moved, bad, bypassed = proof("gem", adapt=True)
    assert bad == 0
    assert bypassed < 16 and skipped > lines * 9 // 10  # the first OFF frames, then planned
