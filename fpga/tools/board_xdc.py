"""A board's board.xdc checked against its chip's package, and PEREGRINE's derived from KESTREL's.

    uv run python tools/board_xdc.py check kestrel                  # its own XDC against xc7z010clg400
    uv run python tools/board_xdc.py derive kestrel peregrine       # check against BOTH packages, then write
                                                                    # boards/microphase_z7_7020/board.xdc

The Z7-Lite comes in a 7010 and a 7020 version of the same PCB (same CLG400 package, same routing), so the
7020's board.xdc is the vendor's 7010 file, IF every pin it names is the same ball on both chips: the pin
exists, its function (`IO_L13P_T2_MRCC_34`: pair, clock capability, bank) is the same, and its bank's I/O
type takes the IOSTANDARD (3.3 V standards need an HR bank). The packages are Xilinx's own pin files
(tools/fetch_board.sh puts them in boards/<dir>/vendor/). Like every board.xdc, the derived file is not
tracked (fpga/.gitignore): this tool is how every tree makes it again.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
from soc import boards  # after the path insert
from soc.platform_z7 import parse_xdc

NEEDS_HR = frozenset({"LVCMOS33", "LVTTL", "TMDS_33"})  # 3.3 V: HR banks only (7-series HP stops at 1.8 V)
OTHER = frozenset({"LVCMOS25", "LVCMOS18", "LVCMOS15", "LVCMOS12", "LVDS_25", "SSTL15", "DIFF_SSTL15"})
USER_IO = frozenset({"HR", "HP"})


@dataclass(frozen=True)
class PkgPin:
    function: str  # the package file's "Pin Name": IO_L13P_T2_MRCC_34
    bank: str
    io_type: str  # HR, HP, CONFIG, MIO, DDR, ...


class BoardXdcError(ValueError):
    pass


def read_pkg(text: str) -> dict[str, PkgPin]:
    """Ball -> PkgPin, from a Xilinx package file (xc7z0x0clg400pkg.txt)."""
    pins: dict[str, PkgPin] = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 8 and f[0] != "Pin" and not line.startswith("Device"):
            pins[f[0]] = PkgPin(f[1], f[3], f[6])
    if not pins:
        raise BoardXdcError("not a Xilinx package file: no pin rows")
    return pins


def check_pin(port: str, ball: str, standard: str | None, pkg: dict[str, PkgPin], part: str) -> list[str]:
    """Every reason `port` on `ball` with `standard` is wrong for `part`; [] when it is right."""
    pin = pkg.get(ball)
    if pin is None:
        return [f"{port}: ball {ball} does not exist on {part}"]
    if pin.io_type not in USER_IO:
        return [f"{port}: ball {ball} is {pin.function} ({pin.io_type}) on {part}, not a user I/O"]
    if standard is not None and standard not in NEEDS_HR | OTHER:
        return [f"{port}: IOSTANDARD {standard} is not one this tool knows: check it by hand"]
    if standard in NEEDS_HR and pin.io_type != "HR":
        return [f"{port}: {standard} needs an HR bank, ball {ball} is in {pin.io_type} bank {pin.bank} on {part}"]
    return []


def check(xdc: str, pkg: dict[str, PkgPin], part: str, same_as: dict[str, PkgPin] | None = None) -> list[str]:
    """Every problem of `xdc` on `part`; with `same_as`, also every ball whose function differs from there."""
    problems: list[str] = []
    for port, (balls, standard) in parse_xdc(xdc).items():
        for ball in balls:
            problems += check_pin(port, ball, standard, pkg, part)
            if same_as is not None and ball in same_as and ball in pkg and same_as[ball] != pkg[ball]:
                problems.append(f"{port}: ball {ball} is {same_as[ball].function} there, {pkg[ball].function} here")
    if not parse_xdc(xdc):
        problems.append("no PACKAGE_PIN in the XDC")
    return problems


def derive(xdc: str, src: boards.Board, dst: boards.Board) -> str:
    """dst's board.xdc: src's, unchanged below a header that says where it came from."""
    head = (
        f"# {dst.name}'s board.xdc: {src.name}'s ({src.directory}/board.xdc), unchanged, written by\n"
        f"# fpga/tools/board_xdc.py after checking every pin on {src.dbpart} and {dst.dbpart} (same PCB).\n"
    )
    return head + xdc


def pkg_path(b: boards.Board) -> Path:
    return FPGA / "boards" / b.directory / "vendor" / f"{b.dbpart}pkg.txt"


def _pkg(b: boards.Board) -> dict[str, PkgPin]:
    path = pkg_path(b)
    if not path.exists():
        raise BoardXdcError(f"{path} not found: run tools/fetch_board.sh {b.name}")
    return read_pkg(path.read_text())


def _xdc(b: boards.Board) -> str:
    if not b.xdc.exists():
        raise BoardXdcError(f"{b.xdc} not found: run tools/fetch_board.sh {b.name}")
    return b.xdc.read_text()


def run(cmd: str, names: list[str]) -> str:
    """The command's report; BoardXdcError with every problem when the XDC is wrong for a part."""
    bs = [boards.get(n) for n in names]
    if cmd == "check":
        problems = check(_xdc(bs[0]), _pkg(bs[0]), bs[0].dbpart)
        if problems:
            raise BoardXdcError("\n".join(problems))
        return f"{bs[0].xdc}: {len(parse_xdc(_xdc(bs[0])))} ports, every pin legal on {bs[0].dbpart}"
    src, dst = bs
    text, have = _xdc(src), _pkg(src)
    problems = check(text, have, src.dbpart) + check(text, _pkg(dst), dst.dbpart, same_as=have)
    if problems:
        raise BoardXdcError("\n".join(problems))
    dst.xdc.write_text(derive(text, src, dst))
    return f"{dst.xdc}: {len(parse_xdc(text))} ports from {src.name}'s, every ball the same on {dst.dbpart}"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").add_argument("board", choices=sorted(boards.BOARDS))
    d = sub.add_parser("derive")
    d.add_argument("src", choices=sorted(boards.BOARDS))
    d.add_argument("dst", choices=sorted(boards.BOARDS))
    a = p.parse_args(argv)
    try:
        print(run(a.cmd, [a.board] if a.cmd == "check" else [a.src, a.dst]))
    except BoardXdcError as e:
        print(f"board_xdc: REFUSED\n{e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
