"""The stereo stream's place in the system table (1.27, tools/host_stereo.py): hostAudioStreamStartStereo,
hostAudioFeedStereo and hostAudioStreamPlayed are host entries APPENDED after 1.26's hostAudioScopes, so
every 1.26 index stands (a 1.26 cart runs) while a cart that streams in stereo or reads the counter calls
them through the table, and an older table (no such row) refuses it. The system serves each with its
host/hstream.h hook; the stub's defaults start nothing and answer 0."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
from host_make import lock_argv  # noqa: E402
if not (FPGA / "gen" / "glass_cart.py").exists():  # a clean tree: the memmap split_image imports
    subprocess.run([*lock_argv(), "make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)
import host_bridges  # noqa: E402  (after gen/ exists)
import host_split  # noqa: E402
import split_image  # noqa: E402
import sys_abi  # noqa: E402
from host_stereo import STEREO
from sys_abi_c import env_rows
from sys_abi_manifest import parse

ROWS = {n: ("host", r, p) for n, (r, p, _) in STEREO.items()}


def test_the_stereo_entries_are_appended_as_a_minor_bump() -> None:
    m = parse(sys_abi.MANIFEST.read_text())
    assert m.version >= (1, 27) and (1, 26) in [v for v, _ in m.history]
    rows = env_rows(m)
    names = [n for n, *_ in rows]
    for n, (r, p, _) in STEREO.items():
        assert (n, "host", r, p) in rows
        assert names.index(n) > names.index("hostAudioScopes"), "1.26's indices moved"
    assert split_image.abi_ok(1 << 16 | 26, 1 << 16 | 27) and not split_image.abi_ok(1 << 16 | 27, 1 << 16 | 26)


def test_a_cart_calls_the_stereo_stream_through_the_table_and_an_older_one_refuses_it() -> None:
    played = host_split.cart_import("hostAudioStreamPlayed", "u32", [], None, ROWS, {})
    assert "zm_sys->fn[ZM_ENV_hostAudioStreamPlayed]" in played and "HOST_AUDIO" not in played
    with pytest.raises(SystemExit, match="host entry"):  # a 1.26 table: no such row
        host_split.cart_import("hostAudioFeedStereo", "void", ["u32", "u32"], None, {}, {})
    with pytest.raises(SystemExit, match="host entry"):  # the float rate of the mono start: not this row
        host_split.cart_import("hostAudioStreamStartStereo", "void", ["f32"], None, ROWS, {})


def test_the_system_serves_them_with_their_hooks_and_the_stub_answers_zero() -> None:
    tail = host_split.system_tail(ROWS, {})
    assert all(f"[ZM_ENV_{n}] = (zm_fn)t_{n}," in tail for n in STEREO)
    assert "return HOST_AUDIO_STREAM_PLAYED(e)" in host_split.forwarder("hostAudioStreamPlayed", "u32", [], None, {})
    assert "HOST_AUDIO_FEED_STEREO(e, a0, a1)" in host_split.forwarder("hostAudioFeedStereo", "void", ["u32", "u32"], None, {})
    assert "#define HOST_AUDIO_STREAM_PLAYED(e) ((void)(e), 0u)" in host_bridges.HOST_DEFAULTS
