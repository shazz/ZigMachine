"""The desk mode (HW 1.17.0, docs/GEM_DESK_MODE.md §7) on the wire: zm_video_out showing plane 0
through the mirror of palette 0, against the machine's own picture (machine/video_desk.zig, built
into tools/desk_ref.zig's reference), across a switch to desk and back mid-frame.

The break tests (ZM_RTL_BREAK=1) each break one rule of the mode (tests/tb/video_desk_mutants.json)
and require the same scenario to fail."""

import json
import os
import shutil
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import video_dump  # noqa: E402
import video_rtl  # noqa: E402

# The compositor's clock at the board's 100 MHz sys against the 40 MHz pixel clock, as the wire tests.
WIRE = (5, 2)
# A misaligned FB_BASE: the low three bits must be dropped on both machines.
FB_BASE = 0x200005
MUTANTS = json.loads((FPGA / "tests" / "tb" / "video_desk_mutants.json").read_text())


@pytest.fixture(scope="session")
def ref() -> Path:
    return video_rtl.desk_ref(FPGA / "build" / "tests" / "desk", FB_BASE)


@pytest.fixture(scope="session")
def desk_tb() -> Path:
    assert (FPGA / "gen" / "memmap.vh").exists(), "run `make memmap` first"
    video_dump.memmap_header()
    return video_rtl.build_tb(desk=True)


def test_desk_frames_on_the_wire_are_the_machines_picture(desk_tb: Path, ref: Path) -> None:
    """Normal, desk from the VBL after a mid-frame write, normal again, then a write between the VBL
    and line 0 that must wait a whole frame: every pixel, no underrun."""
    result = video_rtl.desk_wire(desk_tb, WIRE, ref, FB_BASE)
    assert result.returncode == 0, result.stdout
    assert "(3 desk, 5 normal)" in result.stdout and "-> MATCH" in result.stdout


def test_a_desk_line_holds_a_fetch_too_starved_for_the_picture(desk_tb: Path, ref: Path) -> None:
    """A beat every 16 clocks underruns the picture (test_rtl_video.py); 80 beats a line in one
    line's time do not: the desk's margin (§2 "Clocks and the deadline")."""
    result = video_rtl.desk_wire(desk_tb, WIRE, ref, FB_BASE, starve=16, desk_only=True)
    assert result.returncode == 0, result.stdout
    assert "(3 desk, 1 normal)" in result.stdout


def test_a_starved_desk_fetch_underruns(desk_tb: Path, ref: Path) -> None:
    """The pixels the fetch missed are black, never the bars' colour: the fault stays visible."""
    result = video_rtl.desk_wire(desk_tb, WIRE, ref, FB_BASE, starve=64, desk_only=True)
    assert result.returncode != 0
    assert "underrun 1, 0 bar pixels in the picture" in result.stdout


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize("mutant", MUTANTS, ids=[m["id"] for m in MUTANTS])
def test_a_broken_desk_rule_is_caught(mutant: dict[str, str | int], ref: Path) -> None:
    name, file, old, new = (str(mutant[k]) for k in ("id", "file", "old", "new"))
    work = FPGA / "build" / "tests" / "mutants" / name  # under fpga/build: yowasp's Yosys sees only this tree
    shutil.rmtree(work, ignore_errors=True)
    rtl = work / "rtl"
    shutil.copytree(video_rtl.RTL, rtl)
    text = (rtl / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (rtl / file).write_text(text.replace(old, new))
    video_dump.memmap_header()
    exe = video_rtl.build_tb(rtl, work, desk=True)
    if "starve" in mutant:  # a rule about underruns: the starved run must show the bars in the picture
        result = video_rtl.desk_wire(exe, WIRE, ref, FB_BASE, starve=int(mutant["starve"]), desk_only=True)
        assert " 0 bar pixels in the picture" not in result.stdout, f"{name} went unnoticed:\n{result.stdout}"
        return
    result = video_rtl.desk_wire(exe, WIRE, ref, FB_BASE)
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
