"""The seal (rtl/seal/): the cart CPU's bus windows.

- `zm_seal`, the decision, through Yosys CXXRTL against tests/tb/zm_seal_tb.cpp.
  The window map reaches the testbench as -D's parsed from zm_seal_map.vh; the
  policy is restated in the testbench.
- The sealed VexRiscv (vexgen `:seal`) running tests/seal/ in Verilator: every
  forbidden access traps with the right cause and never reaches the bus
  (tests/test_seal_core.py).

Break tests (ZM_RTL_BREAK=1) break one rule of zm_seal.v at a time and require
the testbench to fail.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
import test_rtl  # after the path insert: reuses its CXXRTL build

BUILD = FPGA / "build" / "tests" / "seal"
SOURCES = ["rtl/seal/zm_seal.v", "rtl/seal/zm_seal_map.vh"]
MAP = FPGA / "rtl/seal/zm_seal_map.vh"
TB = "tests/tb/zm_seal_tb.cpp"
S = "rtl/seal/zm_seal.v"

# (id, text, broken text): each must make the testbench fail.
MUTANTS = [
    ("code_readable", "wire u_r = rodata | u_w;", "wire u_r = rodata | u_w | code;"),
    ("rodata_writable", "wire u_w = data | linear | video;", "wire u_w = data | linear | video | rodata;"),
    ("video_open", "wire u_w = data | linear | video;", "wire u_w = data | linear;"),
    ("user_ignored", "assign r = user ? u_r : 1'b1;", "assign r = 1'b1;"),
    ("m_runs_cart_data", "assign x = user ? u_x : ~u_w;", "assign x = user ? u_x : 1'b1;"),
    ("window_one_bit_wide", "hit = (a >> lg) == (base >> lg);", "hit = (a >> (lg + 1)) == (base >> (lg + 1));"),
    ("window_short", "hit = (a >> lg) == (base >> lg);", "hit = (a >> (lg - 1)) == (base >> (lg - 1));"),
]

_DEFINE = re.compile(r"^`define\s+(ZS_\w+)\s+(?:32'h([0-9a-fA-F_]+)|(\d+))", re.MULTILINE)


def seal_map() -> dict[str, int]:
    """zm_seal_map.vh's `define's as numbers."""
    return {m[1]: int(m[2].replace("_", ""), 16) if m[2] else int(m[3]) for m in _DEFINE.finditer(MAP.read_text())}


def _run(cc: Path) -> subprocess.CompletedProcess[str]:
    exe = cc.parent / "zm_seal_tb"
    defines = [f"-D{k}={v}u" for k, v in seal_map().items()]
    cmd = ["clang++", "-std=c++17", "-O2", f"-I{test_rtl.CXXRTL_INCLUDE}", f"-I{cc.parent}", *defines]
    subprocess.run([*cmd, str(FPGA / TB), "-o", str(exe)], check=True)
    return subprocess.run([str(exe)], capture_output=True, text=True, timeout=300, check=False)


def test_map_parses() -> None:
    m = seal_map()
    assert {"ZS_FW_BASE", "ZS_CODE_BASE", "ZS_LINEAR_LOG2", "ZS_VIDEO_BASE"} <= m.keys()
    assert m["ZS_CODE_BASE"] == 0x40800000


def test_seal_rtl() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    result = _run(test_rtl._cxxrtl("zm_seal", SOURCES[:1], FPGA, BUILD))
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_seal_rule_is_caught(name: str, old: str, new: str) -> None:
    work = BUILD / "mutants" / name  # under fpga/build: yowasp's Yosys sees only this tree
    shutil.rmtree(work, ignore_errors=True)
    for src in SOURCES:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    text = (work / S).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique"
    (work / S).write_text(text.replace(old, new))
    result = _run(test_rtl._cxxrtl("zm_seal", SOURCES[:1], work, work))
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
