"""RTL tests: each module is compiled to C++ by Yosys's CXXRTL backend (yowasp,
so no system simulator is needed) and driven by a C++ testbench in tests/tb/.

A testbench prints its failures and exits non-zero; this file only builds and
runs it. Add a module by adding a row to RTL_TESTS.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
BUILD = FPGA / "build" / "tests"
CXXRTL_INCLUDE = Path(yowasp_yosys.__file__).parent / "share/include/backends/cxxrtl/runtime"

# (top module, its sources, the testbench)
RTL_TESTS = [
    ("zm_vtiming", ["rtl/video/zm_vtiming.v"], "tests/tb/zm_vtiming_tb.cpp"),
    ("zm_tmds_enc", ["rtl/video/zm_tmds_enc.v"], "tests/tb/zm_tmds_tb.cpp"),
    ("hdmi_pattern", ["rtl/video/zm_vtiming.v", "rtl/board/hdmi_pattern.v"], "tests/tb/hdmi_pattern_tb.cpp"),
]


# One rule of an RTL block broken at a time: (id, top, file, text, broken text).
MUTANTS = [
    ("tmds_xnor_tie", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "n1d == 4'd4 && !d[0]", "n1d == 4'd4 && d[0]"),
    ("tmds_balanced_sense", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "balanced ? !m[8]", "balanced ? m[8]"),
    ("tmds_cnt_kept", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "cnt <= 6'sd0;\n            case", "case"),
    ("tmds_token_01", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "10'b0010101011;", "10'b0010101010;"),
    ("tmds_adj_sign", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "(m[8] ? 6'sd0 : -6'sd2)", "(m[8] ? 6'sd0 : 6'sd2)"),
    ("hdmi_edge_off_by_one", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "(x == 10'd799)", "(x == 10'd798)"),
    ("hdmi_ramp_level", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "11'd683", "11'd682"),
    ("hdmi_box_step", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "bx <= bx + 10'd4", "bx <= bx + 10'd3"),
]


def _cxxrtl(top: str, sources: list[str], root: Path = FPGA, build: Path = BUILD) -> Path:
    out = build / f"{top}.cc"
    reads = " ".join(str(root / s) for s in sources)
    script = f"read_verilog -I{FPGA / 'gen'} {reads}; hierarchy -top {top}; proc; write_cxxrtl {out}"
    rc = yowasp_yosys.run_yosys(["-q", "-p", script])
    assert rc == 0, f"yosys failed on {top}"
    return out


def _compile_and_run(top: str, cc: Path, tb: str) -> subprocess.CompletedProcess[str]:
    exe = cc.parent / f"{top}_tb"
    subprocess.run(
        ["clang++", "-std=c++17", "-O2", f"-I{CXXRTL_INCLUDE}", f"-I{cc.parent}", str(FPGA / tb), "-o", str(exe)],
        check=True,
    )
    return subprocess.run([str(exe)], capture_output=True, text=True, timeout=300, check=False)


@pytest.mark.parametrize(("top", "sources", "tb"), RTL_TESTS, ids=[t[0] for t in RTL_TESTS])
def test_rtl(top: str, sources: list[str], tb: str) -> None:
    assert (FPGA / "gen" / "memmap.vh").exists(), "run `make memmap` first"
    BUILD.mkdir(parents=True, exist_ok=True)
    result = _compile_and_run(top, _cxxrtl(top, sources), tb)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "top", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_rule_is_caught(name: str, top: str, file: str, old: str, new: str) -> None:
    sources, tb = next((s, t) for t_, s, t in RTL_TESTS if t_ == top)
    # Under fpga/build, not tmp: yowasp's Yosys is wasm and sees only this tree.
    work = FPGA / "build" / "tests" / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    for src in sources:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    text = (work / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / file).write_text(text.replace(old, new))
    result = _compile_and_run(top, _cxxrtl(top, sources, work, work), tb)
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
