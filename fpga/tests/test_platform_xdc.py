"""The board platform takes its pins from the vendor XDC, so the parser is what
stands between a correct pinout and a bitstream that drives the wrong balls."""

import pytest

from soc import platform_z7
from soc.platform_z7 import BoardXdcMissingError, parse_xdc

XDC = """
## a typical vendor file: one pin per line, buses indexed, -dict form too
set_property PACKAGE_PIN N18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN M14 [get_ports {led[1]}]
set_property PACKAGE_PIN R14 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property -dict { PACKAGE_PIN H16 IOSTANDARD TMDS_33 } [get_ports hdmi_clk_p]
"""


def test_parse_xdc_single_pin_port_keeps_its_pin_and_standard() -> None:
    assert parse_xdc(XDC)["sys_clk"] == (["N18"], "LVCMOS33")


def test_parse_xdc_bus_pins_come_out_in_index_order_not_file_order() -> None:
    pins, _ = parse_xdc(XDC)["led"]
    assert pins == ["R14", "M14"]


def test_parse_xdc_dict_form_reads_the_package_pin() -> None:
    pins, _ = parse_xdc(XDC)["hdmi_clk_p"]
    assert pins == ["H16"]


def test_parse_xdc_comments_and_empty_text_give_no_ports() -> None:
    assert parse_xdc("## nothing here\n") == {}


def test_platform_without_the_board_xdc_refuses_with_where_to_get_it(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    monkeypatch.setattr(platform_z7, "BOARD_XDC", tmp_path / "board.xdc")
    with pytest.raises(BoardXdcMissingError, match="MicroPhase board package"):
        platform_z7.Platform()
