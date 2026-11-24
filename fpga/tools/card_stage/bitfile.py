"""A Xilinx .bit file's header: the part string says which chip the bitstream was built for."""

from __future__ import annotations

import struct

from .errors import CardError

def header(data: bytes) -> dict[str, str]:
    """{'a': design, 'b': part, 'c': date, 'd': time} of a .bit; CardError if it is not one."""
    head = b"\x00\x09\x0f\xf0\x0f\xf0\x0f\xf0\x0f\xf0\x00\x00\x01"
    if data[: len(head)] != head:
        raise CardError("not a .bit file: no Xilinx header at its start")
    at, out = len(head), {}
    while at < len(data) and chr(data[at]) in "abcd":
        key = chr(data[at])
        (n,) = struct.unpack_from(">H", data, at + 1)
        out[key] = data[at + 3 : at + 3 + n].rstrip(b"\0").decode("ascii", "replace")
        at += 3 + n
    if "b" not in out:
        raise CardError("the .bit header names no part")
    return out

def part_of(data: bytes) -> str:
    """The header's part string without the 'xc' prefix and the speed grade: '7z010clg400'."""
    return header(data)["b"].removeprefix("xc").split("-")[0]

def check_board(data: bytes, dbpart: str, board: str, name: str) -> None:
    """Refuse a bitstream built for another chip than `dbpart` ('xc7z010clg400')."""
    have, want = part_of(data), dbpart.removeprefix("xc")
    if have != want:
        raise CardError(f"{name}: a bitstream for part {have}, not {board}'s {want}")
