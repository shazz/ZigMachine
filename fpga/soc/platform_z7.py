"""LiteX platform for the MicroPhase Z7 (XC7Z010-1CLG400), built from the
VENDOR'S OWN XDC rather than from pin numbers typed in here.

Board pinouts are exactly the kind of fact that gets guessed wrong, so this file
holds none: drop the board package's constraint file at
boards/microphase_z7_7010/board.xdc and every `set_property PACKAGE_PIN` /
`IOSTANDARD` pair in it becomes a LiteX IO named after its port. Ports written
`name[i]` become pin `i` of a multi-pin IO `name`.
"""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

from litex.build.generic_platform import IOStandard, Pins
from litex.build.xilinx import XilinxPlatform

FPGA = Path(__file__).resolve().parent.parent
BOARD_XDC = FPGA / "boards/microphase_z7_7010/board.xdc"
DEVICE = "xc7z010clg400-1"

_LINE = re.compile(
    r"^\s*set_property\s+(?P<props>.+?)\s+\[get_ports\s+(?:\{\s*(?P<braced>[^}]+?)\s*\}|(?P<bare>\S+?))\s*\]"
)
_INDEXED = re.compile(r"^(\w+)\[(\d+|\*)\]$")


def _props(text: str) -> dict[str, str]:
    """`-dict { K V K V }` or a single `K V`."""
    text = text.strip()
    if text.startswith("-dict"):
        words = text[len("-dict") :].strip().strip("{}").split()
    else:
        words = text.split()
    return dict(zip(words[0::2], words[1::2], strict=False))


class BoardXdcMissingError(FileNotFoundError):
    def __init__(self) -> None:
        super().__init__(
            f"{BOARD_XDC} not found: copy the constraint file from the MicroPhase board package "
            "(see boards/microphase_z7_7010/README.md)"
        )


def parse_xdc(text: str) -> dict[str, tuple[list[str], str | None]]:
    """Port name -> (pins in index order, IOSTANDARD or None). `name[*]` sets a
    whole bus's IOSTANDARD."""
    pins: dict[str, dict[int, str]] = defaultdict(dict)
    standards: dict[str, str] = {}
    for line in text.splitlines():
        m = _LINE.match(line)
        if not m:
            continue
        port = m.group("braced") or m.group("bare")
        idx = _INDEXED.match(port)
        name, index = (idx.group(1), idx.group(2)) if idx else (port, "0")
        props = _props(m.group("props"))
        if "PACKAGE_PIN" in props and index != "*":
            pins[name][int(index)] = props["PACKAGE_PIN"]
        if "IOSTANDARD" in props:
            standards[name] = props["IOSTANDARD"]
    return {name: ([by_index[i] for i in sorted(by_index)], standards.get(name)) for name, by_index in pins.items()}


def io_from_xdc(text: str) -> list[tuple[object, ...]]:
    """LiteX `_io` entries, one per port, in the XDC's port order."""
    io: list[tuple[object, ...]] = []
    for name, (pins, standard) in parse_xdc(text).items():
        entry: list[object] = [name, 0, Pins(" ".join(pins))]
        if standard:
            entry.append(IOStandard(standard))
        io.append(tuple(entry))
    return io


class Platform(XilinxPlatform):
    def __init__(self, toolchain: str = "vivado") -> None:
        if not BOARD_XDC.exists():
            raise BoardXdcMissingError
        XilinxPlatform.__init__(self, DEVICE, io_from_xdc(BOARD_XDC.read_text()), toolchain=toolchain)
