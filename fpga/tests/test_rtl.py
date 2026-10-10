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

# The HDMI transmitter with audio, the test pattern and tone (rtl/board/hdmi_audio_core.v).
HDMI_SRCS = [f"rtl/hdmi/zm_hdmi_{m}.v" for m in ("acr", "island", "packets", "enc", "tx")]
HDMI_AUDIO_SRCS = [
    "rtl/video/zm_vtiming.v",
    "rtl/video/zm_tmds_enc.v",
    "rtl/board/hdmi_pattern.v",
    "rtl/board/hdmi_tone.v",
    *HDMI_SRCS,
    "rtl/board/hdmi_audio_core.v",
]

# (top module, its sources, the testbench)
RTL_TESTS = [
    ("zm_vtiming", ["rtl/video/zm_vtiming.v"], "tests/tb/zm_vtiming_tb.cpp"),
    ("zm_tmds_enc", ["rtl/video/zm_tmds_enc.v"], "tests/tb/zm_tmds_tb.cpp"),
    (
        "zm_tmds_ser",
        ["rtl/video/zm_tmds_enc.v", "rtl/video/zm_tmds_shift.v", "tests/tb/zm_tmds_ser_top.v"],
        "tests/tb/zm_tmds_ser_tb.cpp",
    ),
    ("hdmi_pattern", ["rtl/video/zm_vtiming.v", "rtl/board/hdmi_pattern.v"], "tests/tb/hdmi_pattern_tb.cpp"),
    (
        "edid_core_top",
        ["rtl/video/zm_vtiming.v", *(f"rtl/board/edid_{m}.v" for m in ("i2c", "reader", "text", "core"))]
        + ["tests/tb/edid_core_top.v"],
        "tests/tb/edid_core_tb.cpp",
    ),
    ("hdmi_audio_core", HDMI_AUDIO_SRCS, "tests/tb/hdmi_audio_tb.cpp"),
    ("hdmi_audio44", [*HDMI_AUDIO_SRCS, "tests/tb/hdmi_audio44_top.v"], "tests/tb/hdmi_audio44_tb.cpp"),
]


# One rule of an RTL block broken at a time: (id, top, file, text, broken text).
MUTANTS = [
    ("tmds_xnor_tie", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "n1d == 4'd4 && !d[0]", "n1d == 4'd4 && d[0]"),
    ("tmds_balanced_sense", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "balanced ? !m[8]", "balanced ? m[8]"),
    ("tmds_cnt_kept", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "cnt <= 6'sd0;\n            case", "case"),
    ("tmds_token_01", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "10'b0010101011;", "10'b0010101010;"),
    ("tmds_adj_sign", "zm_tmds_enc", "rtl/video/zm_tmds_enc.v", "(m[8] ? 6'sd0 : -6'sd2)", "(m[8] ? 6'sd0 : 6'sd2)"),
    ("tmds_ser_msb_first", "zm_tmds_ser", "rtl/video/zm_tmds_shift.v", "q = sh[1:0]", "q = {sh[0], sh[1]}"),
    ("tmds_ser_one_bit", "zm_tmds_ser", "rtl/video/zm_tmds_shift.v", "{2'b00, sh[9:2]}", "{1'b0, sh[9:1]}"),
    ("tmds_ser_period", "zm_tmds_ser", "rtl/video/zm_tmds_shift.v", "ph <= (ph == 3'd4)", "ph <= (ph == 3'd5)"),
    ("hdmi_edge_off_by_one", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "(x == 10'd799)", "(x == 10'd798)"),
    ("hdmi_ramp_level", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "11'd683", "11'd682"),
    ("hdmi_box_step", "hdmi_pattern", "rtl/board/hdmi_pattern.v", "bx <= bx + 10'd4", "bx <= bx + 10'd3"),
    ("edid_no_rstart", "edid_core_top", "rtl/board/edid_reader.v", "S_START, S_RSTART: {", "S_START: {"),
    ("edid_ack_last", "edid_core_top", "rtl/board/edid_reader.v", "8'hFF, n == 8'd255}", "8'hFF, 1'b0}"),
    ("edid_nak_ignored", "edid_core_top", "rtl/board/edid_reader.v", "header && rx[0]", "header && 1'b0"),
    (
        "edid_no_recovery",
        "edid_core_top",
        "rtl/board/edid_reader.v",
        "{OP_XFER, 9'h1FF};  //",
        "{OP_START, 9'h1FF};  //",
    ),
    (
        "edid_rowsum",
        "edid_core_top",
        "rtl/board/edid_reader.v",
        "rowsum[n[7:3]] <= acc + rx[8:1]",
        "rowsum[n[7:3]] <= acc",
    ),
    ("i2c_fast", "edid_core_top", "rtl/board/edid_core.v", "QUARTER = 200", "QUARTER = 100"),
    ("i2c_no_stretch", "edid_core_top", "rtl/board/edid_i2c.v", "!(q == 2'd1 && !scl_s[1])", "1'b1"),
    ("i2c_late_sample", "edid_core_top", "rtl/board/edid_i2c.v", "if (q == 2'd2) rx", "if (q == 2'd3) rx"),
    ("hdmi_ecc_poly", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_island.v", "8'b10000011", "8'b10000111"),
    ("hdmi_no_trailing_guard", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_island.v", "|| ic == 7'd75)", ")"),
    (
        "hdmi_no_leading_guard",
        "hdmi_audio_core",
        "rtl/hdmi/zm_hdmi_island.v",
        "ic == 7'd8 || ic == 7'd9 ||",
        "ic == 7'd9 ||",
    ),
    ("hdmi_bit3", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_island.v", "{k != 5'd0, hbit", "{1'b1, hbit"),
    ("hdmi_terc4", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_enc.v", "terc4 = 10'b0100011110", "terc4 = 10'b0100011100"),
    ("hdmi_data_preamble", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_enc.v", ".c({1'b0, dpre})", ".c({1'b0, 1'b0})"),
    ("hdmi_video_guard", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_enc.v", "{GB_A, GB_B, GB_A}", "{GB_A, GB_A, GB_A}"),
    ("hdmi_guard_early", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_tx.v", "dl[8][2] || dl[7][2]", "dl[8][2] || dl[6][2]"),
    ("hdmi_parity", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_packets.v", "^{l24, cl}", "^{l24}"),
    ("hdmi_frame_wrap", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_packets.v", "fc + n - 8'd192 :", "fc + n - 8'd191 :"),
    ("hdmi_cts", "hdmi_audio_core", "rtl/hdmi/zm_hdmi_acr.v", "cts <= clocks + 20'd1", "cts <= clocks + 20'd2"),
    ("hdmi44_cts_short", "hdmi_audio44", "rtl/hdmi/zm_hdmi_acr.v", "cts <= clocks + 20'd1", "cts <= clocks"),
    ("hdmi44_spc", "hdmi_audio44", "rtl/hdmi/zm_hdmi_tx.v", ".SPC(ACR_N / 128)", ".SPC(ACR_N / 128 + 1)"),
    ("hdmi44_rate", "hdmi_audio44", "tests/tb/hdmi_audio44_top.v", ".RATE_INC(441)", ".RATE_INC(440)"),
    ("hdmi44_cts_twice", "hdmi_audio44", "rtl/hdmi/zm_hdmi_packets.v", "(rst || (load && acr_now))", "(rst)"),
    ("hdmi44_cs_rate", "hdmi_audio44", "rtl/hdmi/zm_hdmi_packets.v", "(CS_48K && f == 8'd25)", "(f == 8'd25)"),
    (
        "hdmi_avi_checksum",
        "hdmi_audio_core",
        "rtl/hdmi/zm_hdmi_packets.v",
        "8'h82 + 8'h02 + 8'h0D",
        "8'h82 + 8'h02 + 8'h0C",
    ),
    ("hdmi_sample_lost", "hdmi_audio44", "rtl/hdmi/zm_hdmi_packets.v", "n <= {2'd0, aud_valid}", "n <= 3'd0"),
    ("hdmi_tone_table", "hdmi_audio_core", "rtl/board/hdmi_tone.v", "012F0065}", "012F0066}"),
    (
        "edid_text_nibble",
        "edid_core_top",
        "rtl/board/edid_text.v",
        "2'd2) {c1, k1} = {hex(rd_data[3:0])",
        "2'd2) {c1, k1} = {hex(rd_data[7:4])",
    ),
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
