"""card.py stage --boot-dir: a card from blank, its BOOT.BIN checked for the board's chip (R41, PEREGRINE)."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
from card_stage import boot, bootbin, stage
from card_stage.errors import CardError
from test_card_tool import fake_bit, fw, request  # noqa: F401  # fw: the fixture

KESTREL_ID, PEREGRINE_ID = 0x13722093, 0x03727093  # a revision nibble on the first: the part ignores it


def fake_bootbin(idcode: int | None) -> bytes:
    head = bytes(0x20) + struct.pack("<I", 0xAA995566) + b"XNLX" + bytes(0x100)
    return head + (b"" if idcode is None else bootbin.WRITE_IDCODE + struct.pack("<I", idcode)) + bytes(16)


def boot_dir(tmp_path: Path, idcode: int | None, skip: str = "") -> Path:
    d = tmp_path / "boot"
    d.mkdir()
    (d / "BOOT.BIN").write_bytes(fake_bootbin(idcode))
    for name in (*boot.NEEDED[1:], *boot.OPTIONAL):
        if name != skip:
            (d / name).write_bytes(name.encode())
    return d


def test_pl_part_reads_the_chip_off_the_fsbls_bitstream_ignoring_the_revision() -> None:
    assert bootbin.pl_part(fake_bootbin(KESTREL_ID), "b") == "xc7z010clg400"
    assert bootbin.pl_part(fake_bootbin(PEREGRINE_ID), "b") == "xc7z020clg400"
    assert bootbin.pl_part(fake_bootbin(None), "b") is None


def test_pl_part_refuses_a_file_that_is_not_a_boot_image_or_a_foreign_chip() -> None:
    with pytest.raises(CardError, match="not a Zynq-7000 boot image"):
        bootbin.pl_part(b"hello" * 20, "b")
    with pytest.raises(CardError, match="IDCODE 0x0372c093"):
        bootbin.pl_part(fake_bootbin(0x0372C093), "b")


def test_check_board_refuses_kestrels_zest_image_for_peregrine() -> None:
    with pytest.raises(CardError, match="loads a xc7z010clg400 bitstream, not peregrine's xc7z020clg400"):
        bootbin.check_board(fake_bootbin(KESTREL_ID), "xc7z020clg400", "peregrine", "b")
    assert "fits every board" in bootbin.check_board(fake_bootbin(None), "xc7z020clg400", "peregrine", "b")


def test_zest_boot_is_each_boards_own_image() -> None:
    assert bootbin.zest_boot("microphase_z7_7020", "xc7z020clg400").parts[-2] == "z7lite_7020"
    assert bootbin.zest_boot("microphase_z7_7010", "xc7z010clg400").parts[-2] == "z7lite_7010"


def test_stage_a_peregrine_card_from_blank_has_boot_files_bit_board_and_carts(tmp_path: Path, fw: Path) -> None:  # noqa: F811
    bit = tmp_path / "p.bit"
    bit.write_bytes(fake_bit("xc7z020clg400-1"))
    req = request(tmp_path, fw, board="peregrine", bit=bit, boot_dir=boot_dir(tmp_path, PEREGRINE_ID))

    up, rows = stage.stage(req)

    listed = set((up / "up_list.txt").read_text().split())
    assert {*boot.NEEDED, *boot.OPTIONAL, "zigmachine.bit", "KESTREL/BOARD"} <= listed
    assert (up / "KESTREL/BOARD").read_text() == "peregrine\n"
    assert any(src.endswith("(bitstream for xc7z020clg400)") for _, src in rows)


def test_stage_refuses_kestrels_boot_bin_on_a_peregrine_card_and_leaves_nothing(tmp_path: Path, fw: Path) -> None:  # noqa: F811
    req = request(tmp_path, fw, board="peregrine", boot_dir=boot_dir(tmp_path, KESTREL_ID))

    with pytest.raises(CardError, match="xc7z010clg400 bitstream"):
        stage.stage(req)
    assert not (tmp_path / "out/card_a").exists()


def test_stage_refuses_a_boot_dir_without_a_kernel(tmp_path: Path, fw: Path) -> None:  # noqa: F811
    with pytest.raises(CardError, match="no zImage"):
        stage.stage(request(tmp_path, fw, boot_dir=boot_dir(tmp_path, None, skip="zImage")))


def test_boot_stage_leaves_the_rootfs_to_an_overlay(tmp_path: Path) -> None:
    up = tmp_path / "up"
    up.mkdir()
    rows = boot.stage(boot_dir(tmp_path, None), up, "v", keep_rootfs=False)
    assert boot.ROOTFS not in [name for name, _ in rows] and (up / "zImage").is_file()
