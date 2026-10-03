"""The openXC7 flow's edits to LiteX's build files (soc/openxc7.py) and the board
core choice (soc/zm_z7.py): pure text, no toolchain."""

from __future__ import annotations

from pathlib import Path

import pytest

from soc import openxc7, zm_z7

LITEX_LINE = "nextpnr-xilinx --json platform_z7.json --xdc platform_z7.xdc --timing-allow-fail --seed 1\n"


def test_seed_replaces_litexs_own_and_keeps_one(tmp_path: Path) -> None:
    script = tmp_path / "build.sh"
    script.write_text(LITEX_LINE)
    openxc7.set_seed(script, 8)
    text = script.read_text()
    assert text.count("--seed") == 1
    assert text.endswith("--seed 8\n")


def test_seed_refuses_a_script_without_one(tmp_path: Path) -> None:
    script = tmp_path / "build.sh"
    script.write_text("nextpnr-xilinx --json x.json\n")
    with pytest.raises(ValueError, match="no --seed"):
        openxc7.set_seed(script, 2)


def test_board_core_choice_standard_means_litexs_own_core() -> None:
    assert zm_z7.core_netlist("standard") is None


def test_board_core_choice_refuses_a_netlist_that_does_not_exist(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError, match="vexgen"):
        zm_z7.core_netlist(str(tmp_path / "VexRiscv_missing.v"))
