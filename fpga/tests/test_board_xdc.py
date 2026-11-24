"""tools/board_xdc.py: PEREGRINE's board.xdc is KESTREL's only if every ball is the same pin on both chips."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import board_xdc
from board_xdc import BoardXdcError, PkgPin

from soc import boards

HEAD = "Device/Package xc7z0x0clg400 9/18/2012\n\nPin  Pin Name  Memory Byte Group  Bank  VCCAUX Group  Super Logic Region  I/O Type  No-Connect\n"
PKG = HEAD + (
    "N18  IO_L13P_T2_MRCC_34  2  34  NA  NA  HR  NA\n"
    "U18  IO_L12P_T1_MRCC_34  1  34  NA  NA  HR  NA\n"
    "R11  DONE_0              NA 0   NA  NA  CONFIG  NA\n"
)
XDC = """set_property PACKAGE_PIN N18 [get_ports PL_CLK_50M]
set_property IOSTANDARD LVCMOS33 [get_ports PL_CLK_50M]
set_property PACKAGE_PIN U18 [get_ports HDMI1_CLK_P]
set_property IOSTANDARD TMDS_33 [get_ports HDMI1_CLK_P]
"""


def test_read_pkg_keeps_each_balls_function_bank_and_io_type() -> None:
    pkg = board_xdc.read_pkg(PKG)
    assert pkg["N18"] == PkgPin("IO_L13P_T2_MRCC_34", "34", "HR")
    assert pkg["R11"].io_type == "CONFIG"
    assert len(pkg) == 3


def test_read_pkg_of_a_file_with_no_pin_rows_is_refused() -> None:
    with pytest.raises(BoardXdcError, match="not a Xilinx package file"):
        board_xdc.read_pkg("hello\n")


def test_check_of_a_legal_xdc_finds_nothing() -> None:
    assert board_xdc.check(XDC, board_xdc.read_pkg(PKG), "p") == []


def test_check_names_a_missing_ball_a_config_ball_and_a_33v_standard_in_an_hp_bank() -> None:
    pkg = board_xdc.read_pkg(PKG)
    pkg["U18"] = PkgPin("IO_L12P_T1_MRCC_35", "35", "HP")
    xdc = XDC + "set_property PACKAGE_PIN Z99 [get_ports X]\nset_property PACKAGE_PIN R11 [get_ports Y]\n"
    problems = "\n".join(board_xdc.check(xdc, pkg, "p"))
    assert "TMDS_33 needs an HR bank, ball U18 is in HP bank 35" in problems
    assert "ball Z99 does not exist on p" in problems
    assert "ball R11 is DONE_0 (CONFIG)" in problems


def test_check_refuses_an_unknown_iostandard_rather_than_guessing() -> None:
    xdc = "set_property -dict { PACKAGE_PIN N18 IOSTANDARD HSTL_I } [get_ports A]\n"
    assert "IOSTANDARD HSTL_I is not one this tool knows" in board_xdc.check(xdc, board_xdc.read_pkg(PKG), "p")[0]


def test_check_against_the_other_chip_names_a_ball_whose_function_moved() -> None:
    have = board_xdc.read_pkg(PKG)
    other = {**have, "N18": PkgPin("IO_L13N_T2_MRCC_34", "34", "HR")}
    problems = board_xdc.check(XDC, other, "p", same_as=have)
    assert problems == ["PL_CLK_50M: ball N18 is IO_L13P_T2_MRCC_34 there, IO_L13N_T2_MRCC_34 here"]


def test_check_of_an_xdc_without_pins_is_a_problem() -> None:
    assert board_xdc.check("# nothing\n", board_xdc.read_pkg(PKG), "p") == ["no PACKAGE_PIN in the XDC"]


def test_derive_keeps_the_vendor_text_below_a_header_naming_both_parts() -> None:
    text = board_xdc.derive(XDC, boards.get("kestrel"), boards.get("peregrine"))
    assert text.endswith(XDC)
    assert "xc7z010clg400 and xc7z020clg400" in text.splitlines()[1]


def _fake_boards(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, xdc: str) -> None:
    monkeypatch.setattr(board_xdc, "FPGA", tmp_path)
    monkeypatch.setattr(boards, "FPGA", tmp_path)
    for b in boards.BOARDS.values():
        (tmp_path / "boards" / b.directory / "vendor").mkdir(parents=True)
        board_xdc.pkg_path(b).write_text(PKG)
    boards.get("kestrel").xdc.write_text(xdc)


def test_run_derive_writes_peregrines_xdc_from_kestrels(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _fake_boards(tmp_path, monkeypatch, XDC)
    assert "2 ports from kestrel's" in board_xdc.run("derive", ["kestrel", "peregrine"])
    assert boards.get("peregrine").xdc.read_text().endswith(XDC)


def test_run_derive_of_a_bad_xdc_writes_nothing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _fake_boards(tmp_path, monkeypatch, XDC + "set_property PACKAGE_PIN Z99 [get_ports X]\n")
    assert board_xdc.main(["derive", "kestrel", "peregrine"]) == 1
    assert not boards.get("peregrine").xdc.exists()


def test_run_without_the_package_file_says_how_to_fetch_it(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _fake_boards(tmp_path, monkeypatch, XDC)
    board_xdc.pkg_path(boards.get("kestrel")).unlink()
    with pytest.raises(BoardXdcError, match="fetch_board.sh kestrel"):
        board_xdc.run("check", ["kestrel"])
