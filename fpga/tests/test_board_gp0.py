"""uboot_serial.quiesce never touches GP0 after a bitstream with nothing behind it (that hangs the ARM)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import uboot_serial as us


class _Con:
    def __init__(self) -> None:
        self.writes: list[tuple[int, int]] = []

    def mw(self, addr: int, value: int) -> None:
        self.writes.append((addr, value))


@pytest.mark.parametrize(
    ("last", "touched"),
    [("build/ym_test_jess/ym_test_top.bit", False), ("build/board_hp/zm_hp_vivado_80.bit", True), (None, True)],
)
def test_quiesce_respects_gp0(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, last: str | None, touched: bool) -> None:
    state = tmp_path / ".board_pl"
    if last is not None:
        state.write_text(last + "\n")
    monkeypatch.setattr(us, "PL_STATE", state)
    monkeypatch.setattr(us, "PAUSE", 0)
    con = _Con()
    us.quiesce(con)  # type: ignore[arg-type]  # [duck-type] a stand-in console with only mw()
    assert (con.writes == [(0x43C00008, 0)]) is touched
