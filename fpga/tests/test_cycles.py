"""The cycles report's arithmetic (tools/cycles_parse.py, cycles_report.py) and
the CSR header generator (tools/cycles_csr.py), on synthetic logs."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import cycles_csr  # after the path insert: tools/ is not a package
import cycles_parse
import cycles_report


def owner(cycles: int, n_in: int, n_out: int) -> str:
    return f"{cycles} 0 0 0 0 0 {n_in} {n_out}"


def log(tmp_path: Path, lines: list[str]) -> Path:
    p = tmp_path / "uart.txt"
    p.write_text("\n".join(lines) + "\n")
    return p


# CAL: 1000 empty spans; each costs 100 cycles inside and 50 outside.
CAL = "ZM CAL 1000 " + " ".join([owner(0, 0, 0)] * 3 + [owner(50_000, 1, 1000), owner(100_000, 1000, 0)])


def test_parse_subtracts_the_probe_cost_per_span_from_each_owner(tmp_path: Path) -> None:
    # cart: 2 spans entered (frame + one HBL), mach: 1 span entered, 1 span entered from it.
    frame = "ZM F 1 " + " ".join([owner(10_200, 2, 0), owner(5_150, 1, 1), owner(0, 0, 0)] + [owner(0, 0, 0)] * 2)
    run = cycles_parse.parse(log(tmp_path, [CAL, frame, "ZM END 0"]))
    assert run.frames[0]["cart"][0] == 10_000  # 10_200 - 2 * 100
    assert run.frames[0]["mach"][0] == 5_000  # 5_150 - 100 - 50
    assert run.end == 0


def test_parse_reports_a_trap_as_fatal(tmp_path: Path) -> None:
    run = cycles_parse.parse(log(tmp_path, [CAL, "ZM TRAP mcause=2 mepc=40000000", "ZM END 3"]))
    assert run.fatal.startswith("ZM TRAP")
    assert run.end == 3


def test_verify_refuses_hashes_that_differ_from_the_oracle(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(cycles_report, "CYC", tmp_path)
    (tmp_path / "ref").mkdir()
    ours = {"frames": 2, "every": 2, "samples": [{"frame": 2, "hash": "aa"}], "total": "t"}
    for kind, sample in (("js", "aa"), ("native", "bb")):
        ref = dict(ours, samples=[{"frame": 2, "hash": sample}])
        (tmp_path / "ref" / f"c.2.2.{kind}.json").write_text(json.dumps(ref))
    run = cycles_parse.Run(json=ours)
    assert cycles_report.verify("c", run) == "MISMATCH-native"


def test_p95_ignores_a_one_off_spike() -> None:
    assert cycles_report.p95([1.0] * 39 + [90.0]) == 1.0
    assert cycles_report.p95([]) is None


def csr(addrs: dict[str, int]) -> dict:
    return {"csr_registers": {n: {"addr": a} for n, a in addrs.items()}}


def test_csr_header_names_every_register_the_firmware_uses() -> None:
    addrs = {n: 0xF000_0000 + 4 * i for i, n in enumerate(cycles_csr.NEEDED)}
    text = cycles_csr.header(csr(addrs))
    assert f"#define CSR_ZM_CYCLES_CYCLES_ADDR 0x{addrs['zm_cycles_cycles']:08x}u" in text


def test_csr_header_refuses_counters_that_are_not_one_array() -> None:
    addrs = {n: 0xF000_0000 + 8 * i for i, n in enumerate(cycles_csr.NEEDED)}
    with pytest.raises(SystemExit, match="contiguous"):
        cycles_csr.header(csr(addrs))
