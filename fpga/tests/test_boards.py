"""soc/boards.py: BOARD picks the part, the XDC and the build directory; KESTREL stays the default."""

import pytest

from soc import boards


def test_unset_board_is_kestrel_with_the_7010_part(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ZM_BOARD", raising=False)
    b = boards.current()
    assert (b.name, b.device, b.dbpart) == ("kestrel", "xc7z010clg400-1", "xc7z010clg400")
    assert b.xdc == boards.FPGA / "boards/microphase_z7_7010/board.xdc"


def test_peregrine_is_the_7020_and_builds_in_its_own_directory(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ZM_BOARD", "peregrine")
    b = boards.current()
    assert b.device == "xc7z020clg400-1"
    assert b.build_dir == boards.FPGA / "build/peregrine"
    assert not b.verified


def test_an_unknown_board_is_refused_not_defaulted(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ZM_BOARD", "gyrfalcon")
    with pytest.raises(boards.UnknownBoardError, match="kestrel, peregrine"):
        boards.current()


def test_make_and_python_agree_on_every_board() -> None:
    """fpga/boards/<dir>/board.mk is what make reads: its PART must be the Python table's."""
    for b in boards.BOARDS.values():
        mk = (boards.FPGA / "boards" / b.directory / "board.mk").read_text()
        assert f"BOARD_PART := {b.device}\n" in mk, b.name
        assert f"BOARD_DBPART := {b.dbpart}\n" in mk, b.name
