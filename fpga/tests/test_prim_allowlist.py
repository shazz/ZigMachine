"""tools/prim_allowlist.py and fpga/silicon_prims.json: the board SoC's netlist may only use cells and
modes proven on silicon (or pending/suspect, which warn), never one known bad or never tested there.
The check against the real netlist is skipped when no board build exists (`make soc-z7`)."""

import json
import sys
import warnings
from collections import Counter
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import prim_allowlist as pa  # after the path insert
import prim_test_read

BOARD_NETLIST = FPGA / "build/soc_z7/gateware/platform_z7.json"
X72 = "RAMB36E1 SDP r72/0 w0/72 RF/RF reg0/0 we1"


def _bits(value: int, width: int) -> str:
    return format(value, f"0{width}b")


def _ram_cell(mode: str, ra: int, wb: int, we_nets: list) -> dict:
    params = {"RAM_MODE": mode, "READ_WIDTH_A": _bits(ra, 32), "READ_WIDTH_B": _bits(0, 32),
              "WRITE_WIDTH_A": _bits(0, 32), "WRITE_WIDTH_B": _bits(wb, 32), "WRITE_MODE_A": "READ_FIRST",
              "WRITE_MODE_B": "READ_FIRST", "DOA_REG": _bits(0, 32), "DOB_REG": _bits(0, 32)}  # fmt: skip
    return {"type": "RAMB36E1", "parameters": params, "connections": {"WEA": ["0"] * 4, "WEBWE": we_nets}}


def _netlist(tmp_path: Path, cells: dict) -> Path:
    path = tmp_path / "n.json"
    path.write_text(json.dumps({"modules": {"top": {"attributes": {"top": "1"}, "cells": cells}}}))
    return path


def test_a_ram_key_names_mode_widths_write_modes_and_byte_enables() -> None:
    assert pa.cell_key("RAMB36E1", _ram_cell("SDP", 72, 72, [7] * 8)) == X72
    assert pa.cell_key("RAMB36E1", _ram_cell("SDP", 72, 72, [7, 7, 8, 8, 9, 9, 10, 10])).endswith("we4")


def test_a_dsp_key_names_opmode_and_the_registers_in_use() -> None:
    params = {"USE_MULT": "MULTIPLY", "USE_SIMD": "ONE48", "USE_DPORT": "FALSE", "MREG": _bits(1, 32),
              "PREG": _bits(1, 32), "AREG": _bits(0, 32)}  # fmt: skip
    ports = {"OPMODE": ["1", "0", "1", "0", "0", "0", "0"], "ALUMODE": ["0"] * 4, "INMODE": [3, 4, "0", "0", "0"]}
    key = pa.cell_key("DSP48E1", {"parameters": params, "connections": ports})
    assert key == "DSP48E1 MULTIPLY ONE48 nod op=0x5 alu=0x0 in=dyn M P"


def test_a_known_bad_mode_fails_the_check(tmp_path: Path) -> None:
    netlist = _netlist(tmp_path, {"a": _ram_cell("SDP", 72, 72, [7] * 8), "s": {"type": "$scopeinfo"}})
    errors, _ = pa.verdict(pa.netlist_keys(netlist), pa.load_allowlist())
    assert len(errors) == 1 and errors[0].startswith(f"BAD on silicon: {X72} (x1)")
    assert pa.main([str(netlist)]) == 1


def test_a_cell_never_on_silicon_fails_and_a_proven_one_passes(tmp_path: Path) -> None:
    errors, warn = pa.verdict(Counter({"OSERDESE2": 4, "FDRE": 10}), pa.load_allowlist())
    assert (
        errors == ["never on silicon: OSERDESE2 (x4): add a lane to make prim-test, run it on the board"] and warn == []
    )


def test_a_suspect_mode_warns_and_fails_only_when_strict(tmp_path: Path) -> None:
    allow = tmp_path / "allow.json"
    allow.write_text(json.dumps({"cells": {"BUFG": {"status": "suspect", "evidence": "why"}}}))
    netlist = _netlist(tmp_path, {"b": {"type": "BUFG", "parameters": {}, "connections": {}}})
    assert pa.main([str(netlist), "--allowlist", str(allow)]) == 0
    assert pa.main([str(netlist), "--allowlist", str(allow), "--strict"]) == 1


def test_an_unknown_status_in_the_allowlist_is_rejected(tmp_path: Path) -> None:
    allow = tmp_path / "allow.json"
    allow.write_text(json.dumps({"cells": {"BUFG": {"status": "ok"}}}))
    with pytest.raises(ValueError, match="status must be one of"):
        pa.load_allowlist(allow)


def test_the_allowlist_marks_x72_bad_and_names_only_real_prim_test_lanes() -> None:
    allow = pa.load_allowlist()
    lanes = {name for name, _ in prim_test_read.LANES}
    assert allow[X72]["status"] == "bad"
    for key, entry in allow.items():
        assert set(entry.get("prim_test", [])) <= lanes, f"{key}: unknown lane in {entry['prim_test']}"


@pytest.mark.skipif(not BOARD_NETLIST.exists(), reason="no board SoC netlist (make soc-z7)")
def test_the_board_soc_uses_no_cell_bad_or_never_seen_on_silicon() -> None:
    errors, warn = pa.verdict(pa.netlist_keys(BOARD_NETLIST), pa.load_allowlist())
    for line in warn:
        warnings.warn(line, stacklevel=1)
    assert errors == [], "\n".join(errors)
