"""A Zynq-7000 BOOT.BIN's part: the IDCODE in the bitstream its FSBL loads before U-Boot.

zeST's BOOT.BIN (what KESTREL boots today) carries a PL partition; its FSBL loads it, and a bitstream for
the other chip fails there, before U-Boot or boot.scr ever runs. zeST ships one image per chip (z7lite_7010,
z7lite_7020): same U-Boot (7 bytes apart, its build date), the same DDR and MIO init. Plan A's U-Boot SPL
image has no PL partition and fits both boards. fpga/boards/microphase_z7_7020/README.md "Boot chain"."""

from __future__ import annotations

import struct
from pathlib import Path

from .errors import CardError

FPGA = Path(__file__).resolve().parent.parent.parent
IDCODES = {0x03722093: "xc7z010clg400", 0x03727093: "xc7z020clg400"}  # UG585 table 6-2, without the revision
WRITE_IDCODE = struct.pack("<I", 0x30018001)  # a Type 1 write of one word to the IDCODE register, as bootgen stores it
ZEST = "zest-bin/zeST-20260518/boards/z7lite_{chip}/boot.bin"


def pl_part(data: bytes, name: str) -> str | None:
    """The part ('xc7z020clg400') the image's bitstream was built for, None if it carries none."""
    if data[0x20:0x28] != struct.pack("<I", 0xAA995566) + b"XNLX":
        raise CardError(f"{name}: not a Zynq-7000 boot image (no width word / XNLX at 0x20)")
    at = data.find(WRITE_IDCODE)
    if at < 0:
        return None
    (idcode,) = struct.unpack_from("<I", data, at + 4)
    part = IDCODES.get(idcode & 0x0FFFFFFF)  # the top nibble is the silicon revision
    if part is None:
        raise CardError(f"{name}: its bitstream is for IDCODE {idcode:#010x}, not a Z7-Lite chip")
    return part


def check_board(data: bytes, dbpart: str, board: str, name: str) -> str:
    """What the image is ('no bitstream' or its part); CardError if its bitstream is for the other chip."""
    part = pl_part(data, name)
    if part is not None and part != dbpart:
        raise CardError(f"{name}: a boot image whose FSBL loads a {part} bitstream, not {board}'s {dbpart}")
    return f"bitstream for {part}" if part else "no bitstream (SPL): fits every board"


def zest_boot(directory: str, dbpart: str) -> Path:
    """zeST's BOOT.BIN for a board (tools/fetch_board.sh puts it in its vendor/)."""
    chip = "7" + dbpart.removeprefix("xc7z")[:3]  # xc7z020clg400 -> '7020'
    return FPGA / "boards" / directory / "vendor" / ZEST.format(chip=chip)
