"""The OSD test bitstream's logic (rtl/board/osd_test_core.v): the HDMI pattern,
the glass OSD over it and the glass registers on GP0, in CXXRTL, driven through
fpga/tools/osd_uboot_demo.sh's steps by tests/tb/osd_test_tb.cpp, every pixel of
a frame checked after each step. `make -C fpga osd-test-sim` writes those
frames as PNGs (tools/osd_test_sim.py).

Break tests (ZM_RTL_BREAK=1) break one rule at a time and require the
testbench to fail, as tests/test_rtl.py does.
"""

import os
import shutil
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
import test_rtl  # after the path insert: reuses its CXXRTL build
import test_rtl_glass  # its runner passes gen/glass_map.py as -D defines

TOP = "osd_test_core"
TB = "tests/tb/osd_test_tb.cpp"
SOURCES = [
    "rtl/video/zm_vtiming.v",
    "rtl/board/hdmi_pattern.v",
    "rtl/video/zm_video_dcram.v",
    "rtl/glass/zm_glass_ptr.v",
    "rtl/glass/zm_glass_regs.v",
    "rtl/glass/zm_glass_osd.v",
    "rtl/board/osd_banner.v",
    "rtl/board/osd_test_core.v",
]
BUILD = FPGA / "build" / "tests" / "osd_test"
B, C = "rtl/board/osd_banner.v", "rtl/board/osd_test_core.v"
# (id, file, text, broken text)
MUTANTS = [
    ("banner_title_inverse", B, "a[8:5] == 4'd0 || a[8:5] == 4'd15", "a[8:5] == 4'd15"),
    ("banner_font_offset", B, "a[7:0] ^ 8'h80", "a[7:0]"),
    ("banner_column_order", B, "8 * (31 - a[4:0])", "8 * a[4:0]"),
    ("osd_off_at_power_on", C, ".CTRL_INIT(ZG_CTRL_OSD)", ".CTRL_INIT(32'd0)"),
    ("arm_writes_lost", C, "banner_we ? banner_waddr : regs_waddr", "banner_waddr"),
]


def run(root: Path, build: Path, args: list[str]) -> tuple[int, str]:
    """Build the testbench against `root`'s sources; returns (exit code, output)."""
    build.mkdir(parents=True, exist_ok=True)
    cc = test_rtl._cxxrtl(TOP, SOURCES, root, build)
    result = test_rtl_glass._run(TOP, cc, TB, [str(test_rtl_glass.FONT), *args])
    return result.returncode, result.stdout + result.stderr


def test_osd_test_core() -> None:
    code, out = run(FPGA, BUILD, [])
    assert code == 0, out


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_osd_test_rule_is_caught(name: str, file: str, old: str, new: str) -> None:
    work = BUILD / "mutants" / name  # under fpga/build: yowasp's Yosys sees only this tree
    shutil.rmtree(work, ignore_errors=True)
    for src in SOURCES:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    text = (work / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / file).write_text(text.replace(old, new))
    code, out = run(work, work, [])
    assert code != 0, f"{name} went unnoticed:\n{out}"
