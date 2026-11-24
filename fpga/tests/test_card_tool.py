"""fpga/tools/card.py: the per-board card stager (repo reorg B4). Fake images, no board, no ssh."""

from __future__ import annotations

import os
import struct
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart
import glass_map
from card_stage import bitfile, cli, install_sh, remote, rootfs, shelf, stage
from card_stage.errors import CardError

V127 = 1 << 16 | 27


def fake_bit(part: str) -> bytes:
    def field(key: bytes, s: str) -> bytes:
        v = s.encode() + b"\0"
        return key + struct.pack(">H", len(v)) + v

    head = b"\x00\x09\x0f\xf0\x0f\xf0\x0f\xf0\x0f\xf0\x00\x00\x01"
    return head + field(b"a", "top;UserID=0") + field(b"b", part) + field(b"c", "2026/11/23") + b"e\0\0\0\4abcd"


def fake_cart(version: int = V127) -> bytes:
    img = bytearray(64)
    struct.pack_into("<I", img, 0, glass_cart.CART_HDR_MAGIC)
    struct.pack_into("<I", img, glass_cart.CART_HDR_VERSION_AT, version)
    struct.pack_into("<I", img, glass_cart.CART_HDR_BSS_END_AT, glass_map.CART_CPU_BASE + glass_cart.CART_IMG_AT + 4096)
    return bytes(img)


def fake_system(version: int = V127) -> bytes:
    return struct.pack("<III", glass_cart.SYS_MAGIC, version, 1) + bytes(64)


@pytest.fixture
def fw(tmp_path: Path) -> Path:
    for tag in ("stniccc", "st_replay"):
        (tmp_path / "fw" / tag).mkdir(parents=True)
        (tmp_path / "fw" / tag / "cart.bin").write_bytes(fake_cart())
    return tmp_path / "fw"


def request(tmp_path: Path, fw_dir: Path, **kw: object) -> stage.Request:
    base = {"board": "kestrel", "name": "card_a", "out": tmp_path / "out", "carts": ["stniccc"], "fw_dir": fw_dir,
            "system": None, "system_version": "1.27"}  # fmt: skip
    return stage.Request(**{**base, **kw})  # type: ignore[arg-type]  # [reportArgumentType] a kwargs bag of the test


def test_stage_a_bootable_cart_writes_up_with_list_sums_install_and_board_file(tmp_path: Path, fw: Path) -> None:
    up, rows = stage.stage(request(tmp_path, fw))

    listed = (up / "up_list.txt").read_text().split()
    assert "CARTS/demos/atari_st/demo-stniccc.zmd" in listed
    assert "KESTREL/BOARD" in listed and (up / "KESTREL/BOARD").read_text() == "kestrel\n"
    assert any(p.startswith("KESTREL/progs/by-hash/") for p in listed)
    assert "card_a" in (up / "install.sh").read_text() and "rollback/card_a" in (up / "install.sh").read_text()
    assert len((up / "MD5SUMS_up").read_text().splitlines()) == len(listed)
    assert not any(b.startswith(stage.BAD) for _, b in rows)


def test_stage_a_data_disk_carries_its_program_disk(tmp_path: Path, fw: Path) -> None:
    up, _ = stage.stage(request(tmp_path, fw, carts=["st_replay"]))

    listed = (up / "up_list.txt").read_text().split()
    assert any(p.startswith("KESTREL/progs/demo-st_replay/BOOT.WSM") for p in listed)


def test_stage_a_system_image_sets_the_version_and_stages_system_rv32(tmp_path: Path, fw: Path) -> None:
    system = tmp_path / "sys.bin"
    system.write_bytes(fake_system())

    up, _ = stage.stage(request(tmp_path, fw, system=system, system_version=None))

    assert (up / "KESTREL/system.rv32").is_file()


def test_stage_refuses_a_system_whose_table_version_is_not_the_carts(tmp_path: Path, fw: Path) -> None:
    system = tmp_path / "sys.bin"
    system.write_bytes(fake_system(1 << 16 | 20))  # the carts need 1.27

    with pytest.raises(CardError, match="1.27.*1.20"):
        stage.stage(request(tmp_path, fw, system=system, system_version=None))
    assert not (tmp_path / "out/card_a").exists()


def test_stage_refuses_a_missing_cart_image_with_nonzero_exit(tmp_path: Path, fw: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (fw / "stniccc/cart.bin").unlink()

    code = cli.main(["stage", "--board", "kestrel", "--name", "x", "--cart", "stniccc", "--system-version", "1.27",
                     "--fw-dir", str(fw), "--out", str(tmp_path / "out")])  # fmt: skip

    assert code == 1 and "MISSING" in capsys.readouterr().err
    assert not (tmp_path / "out/x").exists()


def test_stage_refuses_a_card_name_that_exists(tmp_path: Path, fw: Path) -> None:
    stage.stage(request(tmp_path, fw))

    with pytest.raises(CardError, match="already exists"):
        stage.stage(request(tmp_path, fw))


def test_stage_a_bitstream_for_the_boards_part_is_copied(tmp_path: Path, fw: Path) -> None:
    bit = tmp_path / "a.bit"
    bit.write_bytes(fake_bit("7z010clg400"))

    up, _ = stage.stage(request(tmp_path, fw, bit=bit))

    assert (up / "zigmachine.bit").read_bytes() == bit.read_bytes()


def test_stage_refuses_a_bitstream_for_the_other_boards_part(tmp_path: Path, fw: Path) -> None:
    bit = tmp_path / "a.bit"
    bit.write_bytes(fake_bit("7z020clg400"))

    with pytest.raises(CardError, match="7z020clg400.*kestrel.*7z010clg400"):
        stage.stage(request(tmp_path, fw, bit=bit))
    with pytest.raises(CardError, match="not a .bit"):
        bitfile.part_of(b"nope")
    assert bitfile.part_of(fake_bit("xc7z020clg400-1")) == "7z020clg400"
    stage.stage(request(tmp_path, fw, board="peregrine", name="p", bit=bit))  # the 7020 board takes it


def test_stage_refuses_an_unknown_board_and_a_bad_name(tmp_path: Path, fw: Path) -> None:
    with pytest.raises(CardError, match="unknown board"):
        stage.stage(request(tmp_path, fw, board="falcon"))
    with pytest.raises(CardError, match="card name"):
        stage.stage(request(tmp_path, fw, name="../x"))


def make_base_rootfs(tmp_path: Path) -> Path:
    cpio = rootfs.newc_entry("etc", 0o40755, b"", 1) + rootfs.newc_entry("etc/old", 0o100644, b"old", 2)
    cpio += rootfs.newc_entry("TRAILER!!!", 0, b"", 0)
    base = tmp_path / "base.cpio.uboot"
    base.write_bytes(rootfs.rootfs_glass.ramdisk_image(cpio, 0))
    return base


def test_rootfs_overlay_is_appended_after_the_boards_own_archive(tmp_path: Path, fw: Path) -> None:
    ov = tmp_path / "ov/etc/init.d"
    ov.mkdir(parents=True)
    (ov / "S99wifi").write_bytes(b"new")
    (ov / "S99wifi").chmod(0o755)

    up, _ = stage.stage(request(tmp_path, fw, rootfs_overlay=tmp_path / "ov", rootfs_base=make_base_rootfs(tmp_path)))

    data = rootfs.base_cpio((up / "rootfs.cpio.uboot").read_bytes(), "x")
    assert b"etc/old" in data and b"etc/init.d/S99wifi" in data and data.count(b"TRAILER!!!") == 2
    assert data.index(b"etc/old") < data.index(b"etc/init.d/S99wifi")


def test_rootfs_refuses_a_base_that_is_not_a_uboot_ramdisk(tmp_path: Path) -> None:
    bad = tmp_path / "bad"
    bad.write_bytes(b"x" * 100)
    (tmp_path / "ov").mkdir()
    (tmp_path / "ov/f").write_text("1")

    with pytest.raises(CardError, match="not a U-Boot ramdisk"):
        rootfs.build(bad, tmp_path / "ov", 0)
    (tmp_path / "empty_ov").mkdir()
    with pytest.raises(CardError, match="empty"):
        rootfs.build(make_base_rootfs(tmp_path), tmp_path / "empty_ov", 0)


def rec(tag: str) -> tuple[str, ...]:
    return (f"demos/atari_st/demo-{tag}.zmd", tag.upper(), "g", "2000", "demo", "d")


def test_shelf_merge_appends_new_lines_without_a_second_header() -> None:
    board = "# shelf.txt: header\nA\tA\tg\t1\tt\td\n"

    text, added = shelf.merge(board, ["stniccc"], rec)

    assert added == ["stniccc"] and text.startswith(board)
    assert text.count("#") == 1 and text.endswith("\n")
    assert text.splitlines()[-1].startswith("demos/atari_st/demo-stniccc.zmd\tSTNICCC")


def test_shelf_merge_keeps_the_boards_line_for_a_cart_already_listed() -> None:
    board = "# h\ndemos/atari_st/demo-joust.zmd\tOLD\tg\t1\tt\td\n"

    text, added = shelf.merge(board, ["joust"], rec)

    assert text == board and added == []


def test_shelf_refuses_a_duplicate_line_and_a_comment_in_the_middle() -> None:
    with pytest.raises(CardError, match="duplicate shelf lines: A"):
        shelf.merge("# h\nA\tx\nA\ty\n", ["t"], rec)
    with pytest.raises(CardError, match="comment line in the middle"):
        shelf.merge("# h\nA\tx\n# h again\n", ["t"], rec)


def test_stage_with_shelf_from_writes_the_merged_shelf(tmp_path: Path, fw: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(stage, "_record", rec)
    board = tmp_path / "shelf.txt"
    board.write_text("# h\nA\tA\tg\t1\tt\td\n")

    up, _ = stage.stage(request(tmp_path, fw, shelf_from=board))

    assert (up / "CARTS/shelf.txt").read_text().splitlines()[0] == "# h"
    assert "CARTS/shelf.txt" in (up / "up_list.txt").read_text().split()


def run_install(up: Path, sd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {**os.environ, "ZM_SD": str(sd), "ZM_UP": str(up)}
    return subprocess.run(["sh", str(up / "install.sh"), *args], env=env, capture_output=True, text=True, check=False)


def test_install_sh_copies_files_keeps_the_first_old_copy_and_checks_md5(tmp_path: Path, fw: Path) -> None:
    up, _ = stage.stage(request(tmp_path, fw))
    sd = tmp_path / "sd"
    (sd / "KESTREL").mkdir(parents=True)
    (sd / "KESTREL/system.rv32").write_text("old")  # not staged here: untouched

    r = run_install(up, sd)

    assert r.returncode == 0 and "md5 check: all OK" in r.stdout
    assert (sd / "KESTREL/BOARD").read_text() == "kestrel\n"  # an old KESTREL card: allowed, and written
    assert (sd / "CARTS/demos/atari_st/demo-stniccc.zmd").is_file()
    again = run_install(up, sd)
    assert "md5 check: all OK" in again.stdout
    assert (sd / "KESTREL/rollback/card_a/KESTREL/BOARD").is_file()


def test_install_sh_refuses_a_card_of_another_board(tmp_path: Path, fw: Path) -> None:
    up, _ = stage.stage(request(tmp_path, fw))
    sd = tmp_path / "sd"
    (sd / "KESTREL").mkdir(parents=True)
    (sd / "KESTREL/BOARD").write_text("peregrine\n")

    r = run_install(up, sd)

    assert r.returncode == 1 and "this card is a peregrine card, not kestrel" in r.stdout
    assert not (sd / "CARTS").exists()


def test_install_sh_for_peregrine_refuses_a_card_with_no_board_file(tmp_path: Path) -> None:
    sd, up = tmp_path / "sd", tmp_path / "up"
    sd.mkdir()
    up.mkdir()
    (up / "install.sh").write_text(install_sh.render("p", "peregrine"))

    r = run_install(up, sd)

    assert r.returncode == 1 and "no KESTREL/BOARD" in r.stdout


def test_install_sh_reports_a_md5_mismatch(tmp_path: Path, fw: Path) -> None:
    up, _ = stage.stage(request(tmp_path, fw))
    (up / "KESTREL/BOARD").write_text("kestrel\nTAMPERED")  # after the sums were written
    sd = tmp_path / "sd"
    sd.mkdir()

    assert "MISMATCH" in run_install(up, sd).stdout


def test_install_refuses_a_bad_host_and_a_dir_that_is_not_a_staged_card(tmp_path: Path) -> None:
    with pytest.raises(CardError, match="want user@address"):
        remote.install("-oProxyCommand=x", tmp_path)
    with pytest.raises(CardError, match="no staged card"):
        remote.install("root@192.168.0.15", tmp_path)


def test_install_pushes_over_the_given_ssh_and_needs_the_md5_ok(tmp_path: Path, fw: Path) -> None:
    up, _ = stage.stage(request(tmp_path, fw))
    fake = tmp_path / "fakessh"  # runs the remote command locally, with /tmp/up pointed at a temp dir
    fake.write_text(f'#!/bin/sh\nshift\nexport ZM_SD={tmp_path}/sd ZM_UP={tmp_path}/u\n'
                    f'exec sh -c "$(printf %s "$1" | sed "s#/tmp/up#{tmp_path}/u#g")"\n')  # fmt: skip
    fake.chmod(0o755)
    (tmp_path / "sd").mkdir()

    out = remote.install("root@192.168.0.15", tmp_path / "out/card_a", str(fake))

    assert "md5 check: all OK" in out
    assert (tmp_path / "sd/KESTREL/BOARD").read_text() == "kestrel\n"


def test_card_py_is_a_script_with_a_help(tmp_path: Path) -> None:
    r = subprocess.run([sys.executable, str(FPGA / "tools/card.py"), "stage", "--help"], capture_output=True, text=True, check=False)

    assert r.returncode == 0 and "--rootfs-overlay" in r.stdout
