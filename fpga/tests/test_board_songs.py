"""Every song a cart requests through its input is in its board image (tools/song_pack.py,
docs/FPGA_SOUND_CPU.md "Which songs a cart image holds"). The native host plays sap_test with the
glass's keys through the board's router (ZM_GLASS_KEYS): each song it starts must be in the table
the board firmware links, or BARD answers "ZM SONG MISSING" and the old song plays on."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))

import song_pack

CART = "sap_test"
HOST = FPGA / f"build/host/{CART}/host_audio"
KEY_DOWN = 0x1000000  # gen/glass_map.py
UP, RIGHT, ENTER = 0xE020, 0xE023, 0x0D


def press(frame: int, code: int) -> str:
    return f"{frame}:{KEY_DOWN | code:x},{frame + 1}:{code:x}"


@pytest.fixture(scope="module")
def started(tmp_path_factory: pytest.TempPathFactory) -> list[str]:
    """The songs the native host starts: Warhawk, then Up (to BMX Simulator), Enter, Right (its song 2)."""
    subprocess.run(["make", "-s", "memmap", f"build/host/{CART}/host_audio"], cwd=FPGA, check=True, capture_output=True)
    log = tmp_path_factory.mktemp("songs") / "keys"
    keys = ",".join([press(100, UP), press(110, ENTER), press(120, RIGHT)])
    env = dict(os.environ, ZM_GLASS_KEYS=keys, ZM_AUDIO_LOG=str(log))
    subprocess.run([str(HOST), CART, "160", "160"], env=env, check=True, capture_output=True)
    lines = (log.parent / "keys.w").read_text().splitlines()
    return [line.split(" ", 3)[3] for line in lines if line.startswith("L ")]


def test_the_keys_start_a_second_tune_and_the_board_image_holds_it(started: list[str]) -> None:
    table = song_pack.song_names((ROOT / f"docs/demo-{CART}.wasm").read_bytes(), ROOT / "docs/music")
    assert started[0] == "Warhawk.sap" and started[-1] == "BMX_Simulator.sap"
    assert set(started) <= set(table)


def test_the_packer_refuses_a_started_song_that_is_no_file(tmp_path: Path) -> None:
    with pytest.raises(song_pack.MissingSong, match="Nowhere.sap"):
        song_pack.song_names(b"\0asm", tmp_path, "L 0 24 Nowhere.sap\n")


def test_a_local_song_is_packed_when_present_and_left_out_when_absent(tmp_path: Path) -> None:
    wasm = b"\0asm zm_test.xm\0local.xm\0"
    (tmp_path / "zm_test.xm").write_bytes(b"x")
    assert song_pack.song_names(wasm, tmp_path) == ["zm_test.xm"]
    (tmp_path / "local.xm").write_bytes(b"y")
    assert song_pack.song_names(wasm, tmp_path) == ["local.xm", "zm_test.xm"]


def test_only_the_local_name_is_optional(tmp_path: Path) -> None:
    with pytest.raises(song_pack.MissingSong, match="other.xm"):
        song_pack.song_names(b"\0asm other.xm\0local.xm\0", tmp_path)
