"""tools/board_preflight.py and tools/board_run.py against a fake U-Boot on a pty (a dict memory
answering md.l / mw.l / crc32 / dcache, an hp-test engine model, a diag firmware model) with
openFPGALoader and the XMODEM upload mocked out. Nothing here touches the real board."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import board_preflight as pf
import board_run
import uboot_serial as us
from fake_uboot import FakeUBoot

FW = bytes(range(256)) * 4  # 1 KiB


@pytest.fixture
def board(monkeypatch: pytest.MonkeyPatch) -> FakeUBoot:
    fake = FakeUBoot()
    monkeypatch.setattr(us, "PAUSE", 0)
    loaded: list[str] = []
    monkeypatch.setattr(us, "load_pl", lambda bit: (loaded.append(bit), fake.mem.update({0x43C00000: us.ID_HPTEST})))
    monkeypatch.setattr(pf.us, "load_pl", us.load_pl)
    fake.loaded = loaded
    return fake


def con_for(fake: FakeUBoot, timeout: float = 2.0) -> us.UBoot:
    return us.UBoot(fake.tty, timeout=timeout)


def test_preflight_happy(board: FakeUBoot) -> None:
    results = pf.preflight(con_for(board))
    assert [r.ok for r in results] == [True, True]
    assert board.loaded == [pf.BIT]
    assert pf.report(results) == 0
    assert any("dcache off" in line for line in board.log)
    assert board.mem[0x05100000] == 0x20000000


def test_preflight_ctrl_c_loop(board: FakeUBoot) -> None:
    board.ctrlc_needed = 4
    assert all(r.ok for r in pf.preflight(con_for(board)))
    assert board.ctrlcs >= 4


def test_preflight_wedged_port(board: FakeUBoot, capsys: pytest.CaptureFixture[str]) -> None:
    board.wedged.add(1)
    results = pf.preflight(con_for(board))
    assert [r.ok for r in results] == [True, False]
    assert pf.report(results) == 1
    assert "HP1 WEDGED: press RST KEY" in capsys.readouterr().out


def test_preflight_missing_prompt(board: FakeUBoot, monkeypatch: pytest.MonkeyPatch) -> None:
    board.silent = True
    monkeypatch.setattr(us, "INTERRUPT_LIMIT", 0.5)
    with pytest.raises(us.UBootError, match="no U-Boot prompt"):
        pf.preflight(con_for(board))


def args(fw: Path, **kw: object) -> argparse.Namespace:
    base = {"bit": "x.bit", "fw": str(fw), "diag": None, "hp_cfg": 0, "shot": None, "preflight": False, "secs": 0.5,
            "blit": False, "w64": False}  # fmt: skip
    return argparse.Namespace(**{**base, **kw})


def fw_file(tmp_path: Path) -> Path:
    p = tmp_path / "fw.bin"
    p.write_bytes(FW)
    return p


def fake_loadx(board: FakeUBoot, corrupt: bool = False):
    calls: list[str] = []

    def loadx(self: us.UBoot, path: str, addr: int) -> None:
        calls.append(path)
        for i in range(0, len(FW), 4):
            board.mem[addr + i] = int.from_bytes(FW[i : i + 4], "little") ^ (1 if corrupt and i == 8 else 0)

    return calls, loadx


@pytest.mark.parametrize("mode", [None, 3, 4])
def test_run_happy(board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, mode: int | None) -> None:
    calls, loadx = fake_loadx(board)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    ok, log = board_run.board_run(con_for(board), args(fw_file(tmp_path), diag=mode))
    assert ok, log
    assert len(calls) == 1 and "firmware uploaded" in log[0]
    assert board.log[0] == "mw.l 43c00008 0"  # CTRL 0 before anything is loaded


@pytest.mark.parametrize("blit", [False, True])
def test_run_sets_hp2_afi_only_for_a_blit_bitstream(
    board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, blit: bool
) -> None:
    _, loadx = fake_loadx(board)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    ok, log = board_run.board_run(con_for(board), args(fw_file(tmp_path), blit=blit))
    assert ok, log
    hp2 = [i for i, line in enumerate(board.log) if "0xf800a014 0xf01" in line]
    assert bool(hp2) == blit
    if blit:  # after the HP0/HP1 widths, so after the PL load (the AFI registers hang the ARM before)
        assert hp2[0] > next(i for i, line in enumerate(board.log) if "0xf8009014" in line)


@pytest.mark.parametrize("w64", [False, True])
def test_w64_sets_hp1_64_bit_and_the_dma_together(
    board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, w64: bool
) -> None:
    _, loadx = fake_loadx(board)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    ok, log = board_run.board_run(con_for(board), args(fw_file(tmp_path), diag=3, w64=w64))
    assert ok, log
    wide = [i for i, line in enumerate(board.log) if "0xf8009014 0xf00" in line]
    assert bool(wide) == w64
    if w64:  # after the 32-bit default, and before the cart CPU runs
        assert wide[0] > next(i for i, line in enumerate(board.log) if "0xf8009014 0xf01" in line)
        assert wide[0] < max(i for i, line in enumerate(board.log) if line == "mw.l 43c00008 1")
    assert board.mem[0x05FFFE08] == 0xC0F00000 | (2 if w64 else 0)


def test_preflight_four_ports_tests_hp2_and_hp3(board: FakeUBoot) -> None:
    results = pf.preflight(con_for(board), pf.BIT4, ports=4)
    assert [r.ok for r in results] == [True, True, True, True]
    assert board.mem[0x05200000] == 0x30000000 and board.mem[0x05300000] == 0x40000000
    assert any("0xf800b014 0xf01" in line for line in board.log)


def test_preflight_four_ports_reports_a_wedged_hp2(board: FakeUBoot, capsys: pytest.CaptureFixture[str]) -> None:
    board.wedged.add(2)
    results = pf.preflight(con_for(board), pf.BIT4, ports=4)
    assert [r.ok for r in results] == [True, True, False, True]
    assert pf.report(results) == 1
    assert "HP2 WEDGED: press RST KEY" in capsys.readouterr().out


def test_run_skips_upload_when_crc_matches(board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls, loadx = fake_loadx(board)
    loadx(None, "", board_run.FW_ADDR)  # type: ignore[arg-type]  [the image is already in DDR]
    calls.clear()
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    note = board_run.ensure_firmware(con_for(board), str(fw_file(tmp_path)))
    assert "skipped" in note and not calls


def test_run_crc_mismatch_aborts(board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _, loadx = fake_loadx(board, corrupt=True)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    with pytest.raises(us.UBootError, match="crc mismatch"):
        board_run.board_run(con_for(board), args(fw_file(tmp_path), diag=3))
    assert not any(line.startswith("mw.l 5fffe04") for line in board.log)  # never started


def test_run_diag_hung_reports_wait(board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _, loadx = fake_loadx(board)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    board.diag_broken = True
    ok, log = board_run.board_run(con_for(board), args(fw_file(tmp_path), diag=3, secs=0.3))
    assert not ok and any("HUNG in wait 0x3, AXI STATUS 0x2" in line for line in log)


def test_run_diag_row_mismatch(board: FakeUBoot, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _, loadx = fake_loadx(board)
    monkeypatch.setattr(us.UBoot, "loadx", loadx)
    board.diag_bad = True
    ok, log = board_run.board_run(con_for(board), args(fw_file(tmp_path), diag=3, secs=0.3))
    assert not ok and any(re.match(r"MISMATCH 0x5f80000\+0x8: got 00000000", line) for line in log)


def test_check_needs_lane_on_narrow_reads(board: FakeUBoot) -> None:
    """The real board's false FAIL: CHECK without LANE reads 4-byte beats from the wrong lane (ERRS 32 of 64)."""
    con = con_for(board)
    assert all(r.ok for r in pf.preflight(con))
    assert "mw.l 43c00100 25" in board.log and "mw.l 43c00100 5" not in board.log
    con.mw(0x43C00100, 5)  # the old check, no LANE
    assert con.md(0x43C00128, 1)[0] == 32


def test_cart_passes_with_frames_stuck_at_zero(board: FakeUBoot, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(FakeUBoot, "exec", _no_frames(FakeUBoot.exec))
    board_diag = sys.modules["board_diag"]
    board_diag.start_cart(con_for(board))
    ok, note = board_diag.poll_cart(con_for(board), 0.2)
    assert ok and re.search(r"frames (\d+)->\1$", note)  # [FRAMES not advancing: info only]


def _no_frames(real):
    def exec_(self, w):
        out = real(self, w)
        self.mem[0x05FFFF14] = 0
        return out

    return exec_
