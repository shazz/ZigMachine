"""PAL lists compared as data (cycles/vdlist.h vdl_measure): the lines they skip, and the line whose
colours change under a static picture, which must never skip. Break tests need ZM_RTL_BREAK=1."""

from __future__ import annotations

import os
import re
import subprocess

import pytest
from test_vdirty import FPGA, FRAMES, proof


def test_pal_lists_are_compared_and_skip_their_unchanged_lines() -> None:
    """lockbuster2's zg.copper list carries PAL records: compared word for word (its colours stepped
    over as data, vdlist.h vdl_measure), so its unchanged covered lines skip, not only the borders."""
    lines, skipped, moved, bad, *_ = proof("lockbuster2")
    assert bad == 0 and moved == 0
    assert skipped > 120 * int(FRAMES)  # the borders alone are 80 a frame


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_a_list_read_with_its_colours_as_ops_is_caught() -> None:
    """VD_BREAK=PALWORDS: PAL's colour words read as ops again (alpha 0xFF looks reserved), the list
    is never compared and lockbuster2 skips its borders only."""
    lines, skipped, *_ = proof("lockbuster2", "PALWORDS")
    assert skipped <= 80 * int(FRAMES)


def pal_case(arg: str, mutant: str = "") -> int:
    """host/vdirty_copper_test.c pal / palstatic: covered lines skipped after the first frames."""
    subprocess.run(["make", "-s", "host-vdcopper", f"VD_BREAK={mutant}"], cwd=FPGA, check=True, capture_output=True)
    binary = FPGA / f"build/host/vdcopper/host_vdcopper{'_' + mutant if mutant else ''}"
    out = subprocess.run([str(binary), arg], capture_output=True, text=True, check=False)
    m = re.search(r"VDPAL covered_skipped (\d+)", out.stdout)
    assert m, out.stdout + out.stderr
    return int(m[1])


def test_a_pal_colour_change_under_a_static_picture_is_recomposited() -> None:
    """A PAL record's colour changes every frame, the pixels never: no covered line may skip. The same
    list with a constant colour skips them (the proof is not vacuous)."""
    assert pal_case("pal") == 0
    assert pal_case("palstatic") > 1000


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
def test_a_list_compared_without_its_colours_is_caught() -> None:
    """VD_BREAK=PALCOLOURS: the colour words are left out of the comparison, and covered lines skip
    under a changing colour."""
    assert pal_case("pal", "PALCOLOURS") > 0
