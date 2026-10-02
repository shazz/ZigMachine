"""The glass RTL (rtl/glass/): the ARM's register block and the OSD overlay,
each compiled through Yosys CXXRTL and driven by a C++ testbench in tests/tb/.

The register map reaches the testbenches as -D defines read from
gen/glass_map.py (made from fpga/glass/src/map.zig), so a testbench checks the
map instead of restating it. The OSD testbench reads the machine's font file
itself, so the generated ROM (gen/glass_font.vh) is checked against its source.

Break tests (ZM_RTL_BREAK=1) break one rule at a time and require the
testbench to fail, as tests/test_rtl.py does for the video blocks.
"""

import os
import runpy
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
import test_rtl  # after the path insert: reuses its CXXRTL build

BUILD = FPGA / "build" / "tests" / "glass"
FONT = FPGA.parent / "machine" / "assets" / "fonts" / "system_font_atari_1bit.raw"
DCRAM = "rtl/video/zm_video_dcram.v"

# (top, sources, testbench, arguments)
TESTS = [
    ("zm_glass_regs", ["rtl/glass/zm_glass_regs.v"], "tests/tb/zm_glass_regs_tb.cpp", []),
    ("zm_glass_osd", ["rtl/glass/zm_glass_osd.v", DCRAM], "tests/tb/zm_glass_osd_tb.cpp", [str(FONT)]),
]

R, O = "rtl/glass/zm_glass_regs.v", "rtl/glass/zm_glass_osd.v"
# (id, top, file, text, broken text)
MUTANTS = [
    ("regs_fifo_order", "zm_glass_regs", R, "assign key_data = fifo[rd];", "assign key_data = fifo[wr];"),
    ("regs_full_drop", "zm_glass_regs", R, "if (push && !full) begin", "if (push) begin"),
    ("regs_aw_first", "zm_glass_regs", R, "aw_have ? aw_addr : s_awaddr", "s_awaddr"),
    ("regs_run_reset", "zm_glass_regs", R, "ctrl <= 32'd0;", "ctrl <= 32'd1;"),
    ("regs_bid_echo", "zm_glass_regs", R, "s_bid <= s_awid;", "s_bid <= 12'd0;"),
    ("regs_osd_bound", "zm_glass_regs", R, "< ZG_OSD_CHARS[9:0]", "<= ZG_OSD_CHARS[9:0]"),
    ("regs_flush_kept", "zm_glass_regs", R, "ctrl <= wdata & 32'h3;", "ctrl <= wdata & 32'h7;"),
    ("osd_msb_left", "zm_glass_osd", O, "glyph_row[3'd7 - col2]", "glyph_row[col2]"),
    ("osd_inverse", "zm_glass_osd", O, "^ inv2;", ";"),
    (
        "osd_window",
        "zm_glass_osd",
        O,
        "x < ZG_OSD_X0[10:0] + ZG_OSD_WIDTH[10:0]",
        "x <= ZG_OSD_X0[10:0] + ZG_OSD_WIDTH[10:0]",
    ),
    ("osd_sync_late", "zm_glass_osd", O, "{de_o, hs_o, vs_o} <= sync2;", "{de_o, hs_o, vs_o} <= sync1;"),
    ("osd_enable", "zm_glass_osd", O, "(in2 && en_s[1])", "(in2)"),
    ("osd_line_count", "zm_glass_osd", O, "else if (de_q) {x, y}", "else if (de) {x, y}"),
]


def _defines() -> list[str]:
    gen = FPGA / "gen" / "glass_map.py"
    assert gen.exists(), "run `make memmap` first"
    values = {k: v for k, v in runpy.run_path(str(gen)).items() if k.isupper() and isinstance(v, int)}
    return [f"-D{k}={v}u" for k, v in values.items()]


def _run(top: str, cc: Path, tb: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    exe = cc.parent / f"{top}_tb"
    cmd = ["clang++", "-std=c++17", "-O2", f"-I{test_rtl.CXXRTL_INCLUDE}", f"-I{cc.parent}", *_defines()]
    subprocess.run([*cmd, str(FPGA / tb), "-o", str(exe)], check=True)
    return subprocess.run([str(exe), *args], capture_output=True, text=True, timeout=600, check=False)


@pytest.mark.parametrize(("top", "sources", "tb", "args"), TESTS, ids=[t[0] for t in TESTS])
def test_glass_rtl(top: str, sources: list[str], tb: str, args: list[str]) -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    result = _run(top, test_rtl._cxxrtl(top, sources, FPGA, BUILD), tb, args)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "top", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_glass_rule_is_caught(name: str, top: str, file: str, old: str, new: str) -> None:
    sources, tb, args = next((s, t, a) for t_, s, t, a in TESTS if t_ == top)
    work = BUILD / "mutants" / name  # under fpga/build: yowasp's Yosys sees only this tree
    shutil.rmtree(work, ignore_errors=True)
    for src in sources:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    text = (work / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / file).write_text(text.replace(old, new))
    result = _run(top, test_rtl._cxxrtl(top, sources, work, work), tb, args)
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
