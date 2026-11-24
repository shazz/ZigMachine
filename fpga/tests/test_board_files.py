"""The current board's ($ZM_BOARD, default kestrel) real files, no hardware (R41 B5).

`make test-board BOARD=peregrine` (and build.sh's `boards` gate) run this file once per board. The board
files are not tracked (vendor licences): a check whose files this tree lacks is skipped, never faked."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import board_xdc
from host_make import make_host

from soc import boards

BOARD = boards.current()


def _need(*paths: Path) -> None:
    if missing := [str(p) for p in paths if not p.exists()]:
        pytest.skip(f"not in this tree (tools/fetch_board.sh {BOARD.name}): {', '.join(missing)}")


def test_the_boards_xdc_is_legal_on_its_own_part() -> None:
    _need(BOARD.xdc, board_xdc.pkg_path(BOARD))
    assert "every pin legal on " + BOARD.dbpart in board_xdc.run("check", [BOARD.name])


def test_peregrines_xdc_is_kestrels_below_the_derive_header() -> None:
    src, dst = boards.get("kestrel"), boards.get("peregrine")
    _need(src.xdc, dst.xdc)
    assert dst.xdc.read_text() == board_xdc.derive(src.xdc.read_text(), src, dst)


def test_the_release_soc_generates_for_the_boards_part(tmp_path: Path) -> None:
    """The whole SoC elaborated with the board's parameters (no synthesis): its part in the Vivado script."""
    _need(BOARD.xdc, BOARD.soc.cpu_netlist, BOARD.soc.sound_netlist)
    if not (FPGA / "gen" / "memmap.py").exists():  # a clean tree: the SoC imports gen/
        make_host("memmap")
    cmd = [sys.executable, "-m", "soc.zigmachine_soc", "--target", "z7", "--toolchain", "vivado",
           "--board", BOARD.name, "--release", "--out", str(tmp_path)]  # fmt: skip
    run = subprocess.run(cmd, cwd=FPGA, capture_output=True, text=True, env={**os.environ, "ZM_BOARD": BOARD.name})
    assert run.returncode == 0, run.stderr[-2000:]
    tcl = (tmp_path / "gateware/platform_z7.tcl").read_text()
    assert f"-part {BOARD.device}" in tcl
    assert str(BOARD.soc.cpu_netlist) in tcl and str(BOARD.soc.sound_netlist) in tcl


def test_an_unknown_board_in_the_environment_stops_the_soc_generator() -> None:
    cmd = [sys.executable, "-m", "soc.zigmachine_soc", "--target", "z7", "--release"]
    run = subprocess.run(cmd, cwd=FPGA, capture_output=True, text=True, env={**os.environ, "ZM_BOARD": "gyrfalcon"})
    assert run.returncode != 0 and "unknown board 'gyrfalcon'" in run.stderr
