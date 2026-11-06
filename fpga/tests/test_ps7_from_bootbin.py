"""tools/ps7_from_bootbin.py on a synthetic BOOT.BIN laid out as zeST's FSBL is (1.0, 2.0, 3.0 tables
contiguous, a pointer block naming the 3.0 ones): every register write comes back, in order, in
U-Boot's encoding, and post_config loses only its AFI writes. zeST's own boot.bin is not committed."""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import ps7_from_bootbin as p7

UNLOCK, LOCK = (2, 0xF8000008, 0xDF0D), (2, 0xF8000004, 0x767B)
VIVADO_ORDER = ("mio", "pll", "clock", "ddr", "peripherals")  # ps7_init()'s order too


def stage(kind: str, rev: int) -> list[tuple[int, ...]]:
    body = {
        "mio": [(3, 0xF8000700, 0x3FFF, 0x1600 + rev)],
        "pll": [(3, 0xF8000100, 0x7F000, 0x28000), (4, 0xF800010C, 1)],
        "clock": [(3, 0xF8000128, 0x3F3F01, 0x10000 + rev)],
        "ddr": [(3, 0xF8006000, 0x1FFFF, 0x80 + rev)] * (1 + rev),
        "peripherals": [(3, 0xE0000034, 0xFF, 5), (5, 0xF8F00200, 1)],
        "post_config": [(3, 0xF8000900, 0xF, 0xF), (3, 0xF8008000, 1, 1), (3, 0xF8008014, 1, 1)],
    }[kind]
    return [UNLOCK, *body, LOCK]


def words(ops: list[tuple[int, ...]]) -> list[int]:
    return [w for o in ops for w in ((o[0] << 4) | (len(o) - 1), *o[1:])] + [0]


def boot_image(pointers: bool = True) -> bytes:
    fsbl, at = [0xE59FF018] * 16, {}
    for rev in (1, 2, 3):  # the linker's order in zeST's FSBL
        for k in (*p7.INIT_KINDS, "post_config"):
            at[k, rev] = len(fsbl) * 4
            fsbl += words(stage(k, rev))
    # Vivado's globals, in its order: ps7_{mio,pll,clock,ddr,peripherals}_init_data = ..._3_0
    fsbl += [0xFFFFFFFF] + ([at[k, 3] for k in VIVADO_ORDER] if pointers else [])
    code = struct.pack(f"<{len(fsbl)}I", *fsbl)
    head = bytearray(0x100)
    struct.pack_into("<I4sIIII", head, 0x20, 0xAA995566, b"XNLX", 0, 0x01010000, len(head), len(code))
    return bytes(head) + code


def emitted(c_source: str, name: str) -> list[tuple[int, ...]]:
    body = c_source.split(f"unsigned long ps7_{name}[] = {{")[1].split("};")[0]
    codes = {v: k for k, v in p7.EMIT.items()}
    return [(codes[m[1]], *(int(x.rstrip("U"), 16) for x in m[2].split(", ")))
            for m in re.finditer(r"(EMIT_\w+)\(([^)]+)\)", body)]  # fmt: skip


def test_every_table_comes_back_in_order_for_each_revision(tmp_path: Path) -> None:
    boot = tmp_path / "boot.bin"
    boot.write_bytes(boot_image())
    p7.generate(boot, tmp_path / "ps7_init_gpl.c")
    src = (tmp_path / "ps7_init_gpl.c").read_text()
    for rev in (1, 2, 3):
        for k in p7.INIT_KINDS:
            assert emitted(src, f"{k}_init_data_{rev}_0") == stage(k, rev), (k, rev)
    calls = re.findall(r"ret = ps7_config\(ps7_(\w+)_init_data\);", src)
    assert tuple(calls) == VIVADO_ORDER


def test_post_config_keeps_the_level_shifters_and_drops_the_afi_writes(tmp_path: Path) -> None:
    boot = tmp_path / "boot.bin"
    boot.write_bytes(boot_image())
    p7.generate(boot, tmp_path / "out.c")
    assert emitted((tmp_path / "out.c").read_text(), "post_config_3_0") == [UNLOCK, (3, 0xF8000900, 0xF, 0xF), LOCK]


def test_a_file_that_is_not_a_boot_image_is_refused(tmp_path: Path) -> None:
    boot = tmp_path / "boot.bin"
    boot.write_bytes(bytes(0x200))
    with pytest.raises(ValueError, match="not a Zynq-7000 boot image"):
        p7.generate(boot, tmp_path / "out.c")


def test_without_the_3_0_pointer_block_nothing_is_guessed(tmp_path: Path) -> None:
    boot = tmp_path / "boot.bin"
    boot.write_bytes(boot_image(pointers=False))
    with pytest.raises(ValueError, match="pointer block"):
        p7.generate(boot, tmp_path / "out.c")
    assert not (tmp_path / "out.c").exists()
