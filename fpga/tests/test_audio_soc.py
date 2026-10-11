"""The board SoC's audio tooling (docs/FPGA_AUDIO.md "The SoC"): the import rename
that keeps the players' memory apart (tools/wasm_env_rename.py), the cart's song
bridge table (tools/host_gen.py), the songs linked into the firmware
(tools/song_pack.py), the core's exact rates (soc/zm_audio_soc.py) and the sim
comparison's write check (tools/audio_sim_compare.py), each with its failing case.
The RTL itself is tests/test_rtl_audio.py (`soc_stamped_exact`, the sched_* mutants).
"""

import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA))

import audio_sim_compare
import host_gen
import song_pack
import wasm_env_rename
from soc.zm_audio_soc import rates

AUDIO_WASM = ROOT / "docs/demo-audio.wasm"


def _import_modules(wasm: bytes) -> list[bytes]:
    out, p = [], None
    for sid, start in wasm_env_rename._sections(wasm):
        if sid == wasm_env_rename.IMPORT_SECTION:
            p = start
    n, p = wasm_env_rename._uleb(wasm, p)
    for _ in range(n):
        m, p = wasm_env_rename._uleb(wasm, p)
        out.append(wasm[p : p + m])
        p += m
        f, p = wasm_env_rename._uleb(wasm, p)
        p = wasm_env_rename._skip_desc(wasm, p + f)
    return out


def test_rename_moves_every_env_import_of_the_players_to_aud() -> None:
    data, count = wasm_env_rename.rename(AUDIO_WASM.read_bytes(), b"env", b"aud")
    assert count == 17  # env.memory and the 16 machine* chip calls (13, + the POKEY's three: ABI 1.2.0)
    assert set(_import_modules(data)) == {b"aud"}
    assert len(data) == AUDIO_WASM.stat().st_size


def test_rename_refuses_a_name_of_another_length() -> None:
    with pytest.raises(ValueError, match="same length"):
        wasm_env_rename.rename(AUDIO_WASM.read_bytes(), b"env", b"audio")


def test_song_bridge_lists_the_carts_exports_and_nulls_the_missing() -> None:
    cart = {"pollSongRequest": ("u32", []), "songNamePtr": ("u32", []), "sndhCallD0": ("u32", ["u32"])}
    table = host_gen.song_bridge(cart)
    assert table == (
        "const host_song_bridge host_songs = {w2c_cart_pollSongRequest, w2c_cart_songNamePtr, 0, 0, "
        "0, w2c_cart_sndhCallD0, 0, 0, 0, 0};\n"
    )


def test_song_bridge_refuses_an_export_of_the_wrong_type() -> None:
    assert host_gen.song_bridge({"songTune": ("f32", [])}).count("0") == 10


def test_song_pack_takes_the_logged_songs_and_the_literals_that_exist(tmp_path: Path) -> None:
    (tmp_path / "union").mkdir()
    for n in ("a.sndh", "union/b.mod"):
        (tmp_path / n).write_bytes(b"x")
    wasm = b"\0asm\0\x0bunion/b.mod\0missing.sndh\0"
    names = song_pack.song_names(wasm, tmp_path, "W 0 040 00000001\nL 735 1 a.sndh\nL 9 1 ../x.sndh\n")
    assert names == ["a.sndh", "union/b.mod"]


def test_song_pack_table_is_null_terminated_with_exact_lengths(tmp_path: Path) -> None:
    (tmp_path / "t.ymraw").write_bytes(bytes(range(20)))
    text = song_pack.c_table(["t.ymraw"], tmp_path)
    assert '{"t.ymraw", song0, 20u},' in text and "{0, 0, 0}," in text


def test_rates_are_exact_fractions_of_the_system_clock() -> None:
    assert rates(100_000_000) == {"p_SR_INC": 441, "p_SR_MOD": 1_000_000, "p_YM_INC": 1, "p_YM_MOD": 50}
    assert rates(80_000_000)["p_SR_MOD"] * 44100 == 441 * 80_000_000


def test_rates_refuse_a_clock_below_the_ym() -> None:
    with pytest.raises(ValueError, match="no exact"):
        rates(1_000_000)


NATIVE = [(0, 0x040, 1), (735, 0x020, 0x10), (735, 0x024, 0), (1617, 0x020, 0x0F)]


def test_compare_writes_accepts_the_same_writes_at_the_same_relative_samples() -> None:
    board = [(5000 + t - 735 if t else 4000, a, d) for t, a, d in NATIVE]
    assert audio_sim_compare.compare_writes(NATIVE, (735, 1), board, (5000, 1), 2000) == []


def test_compare_writes_catches_a_dropped_write_and_a_late_one() -> None:
    board = [(4000, 0x040, 1), (5000, 0x020, 0x10), (5000 + 883, 0x020, 0x0F)]
    bad = audio_sim_compare.compare_writes(NATIVE, (735, 1), board, (5000, 1), 2000)
    assert any("024" in b for b in bad) and any("4 writes by the machine, 3" in b for b in bad)
    late = [(4000, 0x040, 1), (5000, 0x020, 0x10), (5001, 0x024, 0), (5882, 0x020, 0x0F)]
    assert audio_sim_compare.compare_writes(NATIVE, (735, 1), late, (5000, 1), 2000)[0].startswith("write 2:")
