"""The boards one SoC tree builds for (repo reorg Part B1, prototypes/repo_reorg/PLAN.md).

`ZM_BOARD` (set by `make BOARD=...`, or `--board` on soc.zigmachine_soc) picks one; the default is
KESTREL, so every command that predates the board parameter builds exactly what it built before.
B2 adds the per-board SoC parameters (D$ size, CHISEL options, BARD FPU...) to `Board`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
DEFAULT = "kestrel"


@dataclass(frozen=True)
class Board:
    name: str
    directory: str  # fpga/boards/<directory>: the physical board (board.xdc, board.mk, README)
    device: str  # the Vivado / LiteX part
    dbpart: str  # openXC7's chipdb name (no speed grade)
    verified: bool  # False until the part and pins are checked against the vendor's package

    @property
    def xdc(self) -> Path:
        return FPGA / "boards" / self.directory / "board.xdc"

    @property
    def build_dir(self) -> Path:
        return FPGA / "build" / self.name


BOARDS: dict[str, Board] = {
    "kestrel": Board("kestrel", "microphase_z7_7010", "xc7z010clg400-1", "xc7z010clg400", verified=True),
    # PEREGRINE: the MicroPhase Z7 with a 7020 (ordered 14 Nov 2026). Part and speed grade unverified
    # until the board and its vendor package are in hand.
    "peregrine": Board("peregrine", "microphase_z7_7020", "xc7z020clg400-1", "xc7z020clg400", verified=False),
}


class UnknownBoardError(ValueError):
    def __init__(self, name: str) -> None:
        super().__init__(f"unknown board {name!r}: one of {', '.join(BOARDS)}")


def get(name: str) -> Board:
    if name not in BOARDS:
        raise UnknownBoardError(name)
    return BOARDS[name]


def current() -> Board:
    """The board `ZM_BOARD` names (KESTREL when unset). An unknown name is an error, never a default."""
    return get(os.environ.get("ZM_BOARD") or DEFAULT)
