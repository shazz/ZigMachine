"""The stream ring's imports in the split images (system table 1.1): zg.audioStreamStart /
audioFeed / audioStreamStop are host entries the system image serves (host/hstream.h), APPENDED
to the 1.0 table, so a 1.0 cart keeps its indices and runs on a 1.1 system, and a lean cart that
streams (st_replay, stream) needs 1.1. Before them, st_replay's lean image did not link: its
cart_env.c called the HOST_AUDIO_* hooks only the monolithic env.c defines."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import host_split
import split_image
import sys_abi
from host_bridges import STREAM
from sys_abi_c import env_rows
from sys_abi_manifest import parse

HOST_ROWS = {n: ("host", r, p) for n, (r, p, _) in STREAM.items()}


def test_the_stream_entries_are_appended_to_1_0_as_a_minor_bump() -> None:
    m = parse(sys_abi.MANIFEST.read_text())
    assert [v for v, _ in m.history][:2] == [(1, 0), (1, 1)] and m.version[0] == 1 and m.version[1] >= 1
    names = [n for n, *_ in env_rows(m)]
    host = [n for n, owner, *_ in env_rows(m) if owner == "host"][: len(STREAM)]  # 1.2 appends the mirror
    assert sorted(host) == sorted(STREAM) and names[names.index(host[0]) :][: len(host)] == sorted(host)
    assert names.index(host[0]) == len(names) - len([n for n, o, *_ in env_rows(m) if o == "host"])  # after 1.0's
    assert split_image.abi_ok(1 << 16, 1 << 16 | 1) and not split_image.abi_ok(1 << 16 | 1, 1 << 16)


def test_a_cart_calls_the_stream_through_the_table_and_refuses_a_table_without_it() -> None:
    feed = host_split.cart_import("hostAudioFeed", "void", ["u32", "u32"], None, HOST_ROWS, {})
    assert "zm_sys->fn[ZM_ENV_hostAudioFeed]" in feed and "HOST_AUDIO" not in feed
    with pytest.raises(SystemExit, match="host entry"):  # a 1.0 table: no such row
        host_split.cart_import("hostAudioFeed", "void", ["u32", "u32"], None, {}, {})
    with pytest.raises(SystemExit, match="host entry"):  # the row with another type
        host_split.cart_import("hostAudioStreamStart", "void", ["u32"], None, HOST_ROWS, {})


def test_the_system_serves_the_stream_entries_with_its_hooks() -> None:
    tail = host_split.system_tail(HOST_ROWS, {})
    assert all(f"[ZM_ENV_{n}] = (zm_fn)t_{n}," in tail for n in STREAM)


def test_st_replays_lean_cart_links() -> None:
    """The regression: make split-cart failed on undefined HOST_AUDIO_FEED / _STREAM_START / _STOP."""
    out = subprocess.run(["make", "-s", "memmap", "split-cart", "CART=st_replay"], cwd=FPGA, capture_output=True,
                         text=True, check=False)  # fmt: skip
    assert out.returncode == 0, out.stdout[-2000:] + out.stderr[-2000:]
    env = (FPGA / "build/host/st_replay/cart_env.c").read_text()
    assert "fn[ZM_ENV_hostAudioFeed]" in env and "HOST_AUDIO_FEED" not in env
