"""The board's dirty-line planner (cycles/vdirty.h), proven natively (host/vdirty_main.c): every
frame the picture the board would keep, where only the lines the planner did not skip are
composited again, is compared whole with a full composite of the same frame. Zero rows may
differ. The carts cover what the planner must see: plane rows (scroll), palettes (joust), the
background and BEAM lines (union_intro, dhs_0pxl0reg), a copper on the top plane (tutorial),
several planes (empire), the GEM pointer drawn over each picture (gem, ZM_VD_CURSOR=1).

The board only plans while planning pays (cycles/vadapt.h): with ZM_VD_ADAPT=1 the proof runs
that bypass on a cost model, and it must engage where nothing can be skipped (medium_overscan,
whose rows are all compared and all new), stay out of the way where most lines are skipped
(gem), and never cost a mismatch across the switches. A plane whose list opens with a PALREF (such
lists always count as changed) has its covered lines new and its rows uncompared, so the plan costs
nothing there; a frame of only such planes (vdirty.h vd_uncompared) is planned without vadapt and
never timed: mpp_truecolor's borders skip in every mode, tcb_colorshock (overscan) is never probed.

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
CARTS = ["scroll", "joust", "union_intro", "dhs_0pxl0reg", "ancool", "empire", "gem"]
LINE = re.compile(
    r"VDIRTY \S+ frames \d+ lines (\d+) skipped (\d+) unknown \d+ moved (\d+) bypassed (\d+) mismatched (\d+) palref (\d+)"
)


def proof(cart: str, mutant: str = "", adapt: bool = False) -> tuple[int, int, int, int, int, int]:
    """(lines, skipped, moved, mismatched, bypassed frames, frames planned with a PALREF plane) over FRAMES."""
    return proof_n(cart, FRAMES, mutant, adapt)


def proof_n(cart: str, frames: str, mutant: str = "", adapt: bool = False) -> tuple[int, int, int, int, int, int]:
    """proof() over `frames` frames."""
    subprocess.run(["make", "-s", "memmap", "host-vdirty", f"CART={cart}", f"VD_BREAK={mutant}"], cwd=FPGA,
                   check=True, capture_output=True)  # fmt: skip
    binary = FPGA / f"build/host/{cart}/host_vdirty{'_' + mutant if mutant else ''}"
    env = dict(os.environ, ZM_VD_CURSOR="1" if cart == "gem" else "0", ZM_VD_ADAPT="1" if adapt else "0")
    out = subprocess.run([str(binary), cart, frames], env=env, capture_output=True, text=True, check=False)
    m = LINE.search(out.stdout)
    assert m, out.stdout + out.stderr
    return int(m[1]), int(m[2]), int(m[3]), int(m[5]), int(m[4]), int(m[6])


@pytest.mark.parametrize("cart", CARTS)
def test_a_skipped_row_is_what_a_full_composite_paints(cart: str) -> None:
    lines, skipped, moved, bad, *_ = proof(cart)
    assert bad == 0 and moved == 0
    assert skipped > 0  # every one of these carts has lines to skip: the proof is not vacuous


@pytest.mark.parametrize("cart", ["tutorial", "fallen_angels", "union_l16", "tcb_colorshock"])
def test_copper_list_frames_skip_only_what_is_unchanged(cart: str) -> None:
    """Copper lists (HW 1.9.0, cycles/vdlist.h): a list compared word for word with last frame's;
    tcb_colorshock's PALREFs always count as changed, the others skip what did not change."""
    lines, skipped, moved, bad, *_ = proof(cart)
    assert bad == 0 and moved == 0 and lines > 0
    assert (skipped == 0) == (cart == "tcb_colorshock")


def test_a_redrawn_plane_skips_its_borders_uncompared() -> None:
    """fallen_angels redraws its plane every frame: it goes hot (vdirty.c plan_plane), its covered
    lines are new without being compared, and its 80 border lines a frame are still skipped."""
    lines, skipped, moved, bad, *_ = proof("fallen_angels")
    assert bad == 0 and moved == 0
    assert skipped >= 80 * (int(FRAMES) - 10)


BREAKS = [("ROWS", "scroll"), ("PAL", "joust"), ("BG", "union_intro"), ("BG", "dhs_0pxl0reg"),
          ("HANDLER", "ancool"), ("PICTURE", "scroll"), ("OVERDRAWN", "gem"),
          ("COPPER", "tutorial"), ("HOT", "scroll")]  # fmt: skip


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("mutant", "cart"), BREAKS)
def test_a_forgotten_input_is_caught(mutant: str, cart: str) -> None:
    assert proof(cart, mutant)[3] > 0


def test_the_plan_is_bypassed_where_it_cannot_pay() -> None:
    lines, skipped, moved, bad, bypassed, _ = proof("medium_overscan", adapt=True)
    assert bad == 0
    assert bypassed >= int(FRAMES) * 9 // 10  # one probe every VA_OFF_FRAMES, the rest bypassed


def test_the_plan_stays_on_where_it_pays() -> None:
    lines, skipped, moved, bad, bypassed, _ = proof("gem", adapt=True)
    assert bad == 0
    assert bypassed < 16 and skipped > lines * 9 // 10  # the first OFF frames, then planned


MPP_FRAMES = "1500"  # mpp_truecolor's modes switch every 480 frames: 1, 1 and 4 planes, then the next picture


def test_palref_planes_skip_their_borders_uncompared() -> None:
    """mpp_truecolor: every plane's list opens with a PALREF. Its covered lines are new, its rows
    uncompared, and its 80 border lines a frame skip in every mode and across the switches; the
    frames are planned without vadapt (none bypassed: a 1 -> 4 plane switch reads as no slow window)."""
    for adapt in (False, True):
        out = proof_n("mpp_truecolor", MPP_FRAMES, adapt=adapt)
        lines, skipped, moved, bad, bypassed, palref = out
        assert bad == 0 and moved == 0
        assert skipped >= 80 * (int(MPP_FRAMES) - 10) and bypassed == 0 and palref == int(MPP_FRAMES)


def test_palref_frames_that_cannot_skip_are_not_probed() -> None:
    """tcb_colorshock: one overscan plane with a PALREF list. Nothing can skip, and its frames are
    planned without vadapt (vd_uncompared), so no probe ever costs it a frame."""
    lines, skipped, moved, bad, bypassed, palref = proof("tcb_colorshock", adapt=True)
    assert bad == 0 and skipped == 0 and bypassed == 0


def test_comparable_lists_are_still_planned() -> None:
    """tutorial's zg.copper list (PAL words, no PALREF) is compared and its frames planned as before."""
    lines, skipped, moved, bad, bypassed, palref = proof("tutorial", adapt=True)
    assert bad == 0 and palref == 0 and skipped > 0


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_a_forgotten_palref_rule_is_caught() -> None:
    """VD_BREAK_PALREF: the rule never sees a PALREF, so mpp_truecolor's rows are compared, its frames
    go back to vadapt, and the plan, which cannot pay, is bypassed: the borders stop skipping."""
    lines, skipped, moved, bad, bypassed, palref = proof_n("mpp_truecolor", MPP_FRAMES, "PALREF", adapt=True)
    assert palref == 0 and bypassed > 0
    assert skipped < 80 * (int(MPP_FRAMES) - 10)  # test_palref_planes_skip_their_borders_uncompared fails on it
